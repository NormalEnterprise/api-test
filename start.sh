#!/bin/bash

# Define variables
IMAGE_NAME="api:latest"
CONTAINER_NAME="api-test"
PORT=8000
FORCE_REBUILD=true  # Set to true to always rebuild the image

# Check if podman is installed
if ! command -v podman &> /dev/null; then
    echo "Error: podman is not installed. Please install podman first."
    exit 1
fi

# Always build the image if FORCE_REBUILD is true
if [ "$FORCE_REBUILD" = true ] || ! podman image exists ${IMAGE_NAME}; then
    echo "Building image ${IMAGE_NAME}..."
    podman build -t ${IMAGE_NAME} .
    if [ $? -ne 0 ]; then
        echo "Error: Failed to build the image."
        exit 1
    fi
    echo "Image built successfully."
fi

# Check if the container is already running
if podman container exists ${CONTAINER_NAME}; then
    echo "Container ${CONTAINER_NAME} already exists. Stopping and removing it..."
    podman stop ${CONTAINER_NAME}
    podman rm ${CONTAINER_NAME}
fi

# Run the container
echo "Starting container ${CONTAINER_NAME}..."
podman run -d --name ${CONTAINER_NAME} -p ${PORT}:${PORT} ${IMAGE_NAME}

if [ $? -eq 0 ]; then
    echo "Container started successfully. The application is accessible at http://localhost:${PORT}"
else
    echo "Error: Failed to start the container."
    exit 1
fi 