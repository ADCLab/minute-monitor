#!/usr/bin/env bash
set -euo pipefail

# -------- Config (env vars) --------
INTERVAL_SECONDS="${INTERVAL_SECONDS:-60}"
PUSH_TO_API="${PUSH_TO_API:-false}"
DATA_DIR="${DATA_DIR:-/data}"
API_URL="${API_URL:-}"
API_TOKEN="${API_TOKEN:-}"
CAMERA_DEVICE="${CAMERA_DEVICE:-/dev/video0}"
RESOLUTION="${RESOLUTION:-1280x720}"
JPEG_QUALITY="${JPEG_QUALITY:-90}"

# Max size + pruning
MAX_DATA_SIZE="${MAX_DATA_SIZE:-0}"     # e.g., "5G", "500M", "1000000000", or "0" for unlimited
PRUNE_MODE="${PRUNE_MODE:-none}"        # none | keep_last | max_age
KEEP_LAST_N="${KEEP_LAST_N:-0}"         # used when PRUNE_MODE=keep_last
MAX_AGE_DAYS="${MAX_AGE_DAYS:-0}"       # used when PRUNE_MODE=max_age

# -------- Helpers --------
log() { echo "[$(date -Iseconds)] $*"; }

is_true() {
  case "${1,,}" in
    true|1|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

# Parse sizes like "500M", "5G", "10K", "123456"
# Supports suffixes: K, M, G, T (base-1024). Also supports KiB/MiB/GiB/TiB.
parse_size_to_bytes() {
  local s="${1}"
  s="${s//[[:space:]]/}"     # remove spaces
  s="${s^^}"                 # uppercase

  if [[ "$s" == "" || "$s" == "0" ]]; then
    echo 0
    return 0
  fi

  # Pure integer -> bytes
  if [[ "$s" =~ ^[0-9]+$ ]]; then
    echo "$s"
    return 0
  fi

  # Match number + suffix
  if [[ "$s" =~ ^([0-9]+)(K|M|G|T|KIB|MIB|GIB|TIB)$ ]]; then
    local num="${BASH_REMATCH[1]}"
    local suf="${BASH_REMATCH[2]}"
    local mul=1
    case "$suf" in
      K|KIB)   mul=$((1024)) ;;
      M|MIB)   mul=$((1024**2)) ;;
      G|GIB)   mul=$((1024**3)) ;;
      T|TIB)   mul=$((1024**4)) ;;
    esac
    echo $((num * mul))
    return 0
  fi

  echo "ERROR"
  return 1
}

# Current size of DATA_DIR in bytes (GNU du supports -sb)
dir_size_bytes() {
  # If directory is empty/nonexistent, treat as 0
  if [ ! -d "$DATA_DIR" ]; then
    echo 0
    return 0
  fi
  du -sb "$DATA_DIR" 2>/dev/null | awk '{print $1}'
}

# Size of file in bytes
file_size_bytes() {
  stat -c%s "$1"
}

# Delete files to keep only last N images (by modification time)
prune_keep_last() {
  local n="$1"
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ]; then
    log "PRUNE keep_last skipped: KEEP_LAST_N must be >= 1 (got: $n)"
    return 0
  fi

  # List capture files newest-first; delete everything beyond N
  # Uses find->sort for safer handling than plain ls
  mapfile -t files < <(find "$DATA_DIR" -maxdepth 1 -type f -name 'capture_*.jpg' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk '{print $2}')
  local count="${#files[@]}"

  if [ "$count" -le "$n" ]; then
    log "PRUNE keep_last: $count files <= $n, nothing to delete"
    return 0
  fi

  log "PRUNE keep_last: keeping newest $n of $count files, deleting $((count - n)) older files"
  for ((i=n; i<count; i++)); do
    rm -f -- "${files[$i]}" || true
  done
}

# Delete files older than D days
prune_max_age() {
  local d="$1"
  if ! [[ "$d" =~ ^[0-9]+$ ]] || [ "$d" -lt 1 ]; then
    log "PRUNE max_age skipped: MAX_AGE_DAYS must be >= 1 (got: $d)"
    return 0
  fi

  log "PRUNE max_age: deleting capture_*.jpg older than $d days"
  # -mtime +d means strictly greater than d*24 hours old
  find "$DATA_DIR" -maxdepth 1 -type f -name 'capture_*.jpg' -mtime +"$d" -print -delete 2>/dev/null || true
}

prune_if_configured() {
  case "${PRUNE_MODE,,}" in
    none)
      return 0
      ;;
    keep_last)
      prune_keep_last "$KEEP_LAST_N"
      ;;
    max_age)
      prune_max_age "$MAX_AGE_DAYS"
      ;;
    *)
      log "WARN: Unknown PRUNE_MODE='$PRUNE_MODE' (expected none|keep_last|max_age). No pruning done."
      return 0
      ;;
  esac
}

# Enforce max size before moving TMPFILE into DATA_DIR
# If limit is exceeded, attempt pruning; if still exceeded -> exit
enforce_max_size_or_exit() {
  local max_bytes="$1"
  local incoming_bytes="$2"

  if [ "$max_bytes" -le 0 ]; then
    return 0
  fi

  local current
  current="$(dir_size_bytes)"

  # Predict size after adding incoming file
  local predicted=$((current + incoming_bytes))

  if [ "$predicted" -lt "$max_bytes" ]; then
    return 0
  fi

  log "WARN: Data dir would exceed MAX_DATA_SIZE (current=${current}B + incoming=${incoming_bytes}B >= max=${max_bytes}B). Attempting prune mode: ${PRUNE_MODE}"

  prune_if_configured

  current="$(dir_size_bytes)"
  predicted=$((current + incoming_bytes))

  if [ "$predicted" -ge "$max_bytes" ]; then
    log "ERROR: Max data size reached and pruning insufficient (predicted=${predicted}B >= max=${max_bytes}B). Stopping."
    exit 2
  fi
}

# -------- Validation --------
if ! [[ "$INTERVAL_SECONDS" =~ ^[0-9]+$ ]] || [ "$INTERVAL_SECONDS" -lt 1 ]; then
  echo "ERROR: INTERVAL_SECONDS must be an integer >= 1 (got: $INTERVAL_SECONDS)" >&2
  exit 1
fi

MAX_BYTES="$(parse_size_to_bytes "$MAX_DATA_SIZE" || true)"
if [ "$MAX_BYTES" = "ERROR" ]; then
  echo "ERROR: MAX_DATA_SIZE must be bytes or use suffix K/M/G/T (e.g., 500M, 5G). Got: $MAX_DATA_SIZE" >&2
  exit 1
fi

if is_true "$PUSH_TO_API"; then
  if [ -z "$API_URL" ]; then
    echo "ERROR: PUSH_TO_API=true requires API_URL to be set" >&2
    exit 1
  fi
else
  mkdir -p "$DATA_DIR"
fi

if [ ! -e "$CAMERA_DEVICE" ]; then
  echo "ERROR: Camera device not found at $CAMERA_DEVICE" >&2
  echo "Hint: run container with --device=/dev/video0:/dev/video0" >&2
  exit 1
fi

log "Starting capture loop"
log "INTERVAL_SECONDS=$INTERVAL_SECONDS | PUSH_TO_API=$PUSH_TO_API | MAX_DATA_SIZE=$MAX_DATA_SIZE (${MAX_BYTES}B) | PRUNE_MODE=$PRUNE_MODE"

while true; do
  EPOCH="$(date +%s)"
  FILENAME="capture_${EPOCH}.jpg"
  TMPFILE="/tmp/${FILENAME}"

  # Capture a single frame to tmp
  if fswebcam \
      --no-banner \
      -d "$CAMERA_DEVICE" \
      -r "$RESOLUTION" \
      --jpeg "$JPEG_QUALITY" \
      "$TMPFILE" >/dev/null 2>&1; then
    log "Captured $TMPFILE"
  else
    log "WARN: Capture failed. Retrying after interval..."
    sleep "$INTERVAL_SECONDS"
    continue
  fi

  if is_true "$PUSH_TO_API"; then
    log "Uploading to API: $API_URL"

    AUTH_HEADER=()
    if [ -n "$API_TOKEN" ]; then
      AUTH_HEADER=(-H "Authorization: Bearer $API_TOKEN")
    fi

    if curl -fsS "${AUTH_HEADER[@]}" \
        -F "file=@${TMPFILE};type=image/jpeg" \
        -F "filename=${FILENAME}" \
        -F "timestamp=${EPOCH}" \
        "$API_URL" >/dev/null; then
      log "Upload successful: $FILENAME"
      rm -f "$TMPFILE"
    else
      log "ERROR: Upload failed; keeping file at $TMPFILE for debugging"
    fi
  else
    # Enforce max folder size before saving
    INCOMING_BYTES="$(file_size_bytes "$TMPFILE")"
    enforce_max_size_or_exit "$MAX_BYTES" "$INCOMING_BYTES"

    DEST="${DATA_DIR%/}/${FILENAME}"
    mv "$TMPFILE" "$DEST"
    log "Saved to disk: $DEST"
  fi

  sleep "$INTERVAL_SECONDS"
done