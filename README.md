***

# 📸 Minute Monitor

A lightweight Dockerized webcam capture service that takes a picture every N seconds, saves it locally **or** uploads it to an API endpoint. Includes automatic storage limits and optional pruning rules to prevent filling local storage.

***

## 🚀 Features

*   Capture webcam images at a configurable interval
*   Save images to disk **or** upload them to an API
*   Unix timestamp filenames
*   Enforce maximum data directory size (e.g., `5G`, `500M`, etc.)
*   Optional pruning:
    *   **keep\_last** → preserve only newest N images
    *   **max\_age** → delete images older than D days
*   Fully configurable with environment variables
*   Supports V4L2 webcams (`/dev/video0`)

***

## 🐳 Getting the Image

Pull from Docker Hub:

```bash
docker pull adclab/minute-monitor:latest
```

Or pin a specific version:

```bash
docker pull adclab/minute-monitor:v0.1
```

***

## ▶️ Usage

### 📁 Save images to disk

```bash
docker run --rm \
  --device=/dev/video0:/dev/video0 \
  -e INTERVAL_SECONDS=60 \
  -e PUSH_TO_API=false \
  -v "$(pwd)/data:/data" \
  adclab/minute-monitor:latest
```

***

### 🌐 Upload images to an API

```bash
docker run --rm \
  --device=/dev/video0:/dev/video0 \
  -e INTERVAL_SECONDS=60 \
  -e PUSH_TO_API=true \
  -e API_URL="https://example.com/upload" \
  -e API_TOKEN="optional-token" \
  adclab/minute-monitor:latest
```

***

# 📦 Docker‑Compose Example

Create a file named **docker-compose.yml**:

```yaml
version: "3.9"

services:
  minute-monitor:
    image: adclab/minute-monitor:latest

    # Give the container access to your webcam
    devices:
      - "/dev/video0:/dev/video0"

    # Restart automatically unless manually stopped
    restart: unless-stopped

    # Persist images on host
    volumes:
      - ./data:/data

    environment:
      # --- Core settings ---
      INTERVAL_SECONDS: 60
      PUSH_TO_API: "false"
      CAMERA_DEVICE: "/dev/video0"
      RESOLUTION: "1280x720"
      JPEG_QUALITY: 90

      # --- Storage limit ---
      MAX_DATA_SIZE: "5G"

      # --- Pruning options (choose ONE mode) ---
      #PRUNE_MODE: "none"

      # Keep last N images
      #PRUNE_MODE: "keep_last"
      #KEEP_LAST_N: 10000

      # Delete images older than D days
      #PRUNE_MODE: "max_age"
      #MAX_AGE_DAYS: 7

      # --- API upload mode (optional) ---
      #PUSH_TO_API: "true"
      #API_URL: "https://example.com/upload"
      #API_TOKEN: "my_secret_token"
```

***

## ⚙️ Configuration

### Core Environment Variables

| Variable           | Default       | Description                         |
| ------------------ | ------------- | ----------------------------------- |
| `INTERVAL_SECONDS` | `60`          | Time between captures               |
| `PUSH_TO_API`      | `false`       | If `true`, upload instead of saving |
| `DATA_DIR`         | `/data`       | Directory where images are stored   |
| `CAMERA_DEVICE`    | `/dev/video0` | Webcam device                       |
| `RESOLUTION`       | `1280x720`    | Image resolution                    |
| `JPEG_QUALITY`     | `90`          | JPEG quality                        |

***

## API Upload Variables

| Variable    | Default | Description           |
| ----------- | ------- | --------------------- |
| `API_URL`   | `""`    | Upload endpoint       |
| `API_TOKEN` | `""`    | Optional Bearer token |

***

## Storage Limit + Pruning

| Variable        | Default | Description                                                             |
| --------------- | ------- | ----------------------------------------------------------------------- |
| `MAX_DATA_SIZE` | `0`     | Max size of `/data` folder. 0 = unlimited. Supports `M`, `G`, `T`, etc. |
| `PRUNE_MODE`    | `none`  | `none`, `keep_last`, or `max_age`                                       |
| `KEEP_LAST_N`   | `0`     | Keep only newest N images                                               |
| `MAX_AGE_DAYS`  | `0`     | Delete images older than D days                                         |

***

## 🧹 Pruning Examples

### Keep last 10,000 images

```bash
-e PRUNE_MODE=keep_last
-e KEEP_LAST_N=10000
```

### Delete images older than 7 days

```bash
-e PRUNE_MODE=max_age
-e MAX_AGE_DAYS=7
```

### Hard stop when reaching 5GB

```bash
-e MAX_DATA_SIZE=5G
```

***

## 🔍 Finding Your Webcam Device on Linux

Minute Monitor uses **V4L2** (Video4Linux2), which exposes webcams under:

    /dev/video0
    /dev/video1
    /dev/video2
    ...

Follow these steps to identify the correct device.

***

### 1. List Available Video Devices

```bash
ls /dev/video*
```

Example:

    /dev/video0

***

### 2. View Device Details with `v4l2-ctl` (Recommended)

Install V4L2 utilities:

```bash
sudo apt install v4l-utils
```

Then list devices:

```bash
v4l2-ctl --list-devices
```

***

### 3. Check Kernel Messages with `dmesg`

```bash
dmesg | grep -i video
```

Look for:

    /dev/video0 created

***

### 4. Verify with `lsusb`

```bash
lsusb
```

Example:

    Bus 003 Device 004: ID 046d:0825 Logitech, Inc. Webcam C270

***

### 5. Test Capturing a Frame (Optional)

Using `fswebcam`:

```bash
sudo apt install fswebcam
fswebcam test.jpg
```

Using `ffmpeg`:

```bash
ffmpeg -f v4l2 -i /dev/video0 -frames:v 1 test.jpg
```

***

## 🤝 Contributing & Forking

Issues and pull requests welcome, but unsure how much time I have to implement because of work.  
Everyone is encouraged to fork and extend the project.

***
