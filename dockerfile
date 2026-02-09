FROM debian:bookworm-slim

# Install fswebcam for capture, curl for API upload, ca-certs for HTTPS
RUN apt-get update && apt-get install -y --no-install-recommends \
    fswebcam \
    curl \
    ca-certificates \
    tzdata \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy entrypoint script
COPY capture.sh /app/capture.sh
RUN chmod +x /app/capture.sh

# Create data directory (you should mount a volume here)
RUN mkdir -p /data

# Default environment variables
ENV INTERVAL_SECONDS=60 \
    PUSH_TO_API=false \
    DATA_DIR=/data \
    API_URL="" \
    API_TOKEN="" \
    CAMERA_DEVICE=/dev/video0 \
    RESOLUTION=1280x720 \
    JPEG_QUALITY=90 \
    WRITE_LATEST=true \
    MAX_DATA_SIZE=0 \
    PRUNE_MODE=none \
    KEEP_LAST_N=0 \
    MAX_AGE_DAYS=0 

ENTRYPOINT ["/app/capture.sh"]