FROM debian:bookworm-slim

# Install capture + upload tools and BusyBox for httpd
RUN apt-get update && apt-get install -y --no-install-recommends \
    fswebcam curl ca-certificates busybox tzdata \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy entrypoint
COPY capture.sh /app/capture.sh
RUN chmod +x /app/capture.sh

# Data folder for images
RUN mkdir -p /data

# Default environment
ENV INTERVAL_SECONDS=60 \
    PUSH_TO_API=false \
    DATA_DIR=/data \
    API_URL="" \
    API_TOKEN="" \
    CAMERA_DEVICE=/dev/video0 \
    RESOLUTION=1920x1080 \
    JPEG_QUALITY=90 \
    MAX_DATA_SIZE=0 \
    PRUNE_MODE=none \
    KEEP_LAST_N=0 \
    MAX_AGE_DAYS=0 \
    SERVE_LATEST=true \
    SERVER_PORT=8080

EXPOSE 8080

ENTRYPOINT ["/app/capture.sh"]