#!/bin/bash

# Set variables here
REPO="adclab/minute-monitor"
VERSION="v0.2"

# Build image with both tags
docker build \
  -t ${REPO}:${VERSION} \
  -t ${REPO}:latest \
  .

# Push both tags
docker push ${REPO}:${VERSION}
docker push ${REPO}:latest