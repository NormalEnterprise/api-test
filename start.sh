#!/bin/bash

# Define variables
IMAGE_NAME="api:latest"
CONTAINER_NAME="api-test"
PORT=8000
FORCE_REBUILD=true  # Set to true to always rebuild the image

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: docker is not installed. Please install docker first."
    exit 1
fi

# Always build the image if FORCE_REBUILD is true
if [ "$FORCE_REBUILD" = true ] || ! docker image inspect ${IMAGE_NAME} &> /dev/null; then
    echo "Building image ${IMAGE_NAME}..."
    docker build -t ${IMAGE_NAME} .
    if [ $? -ne 0 ]; then
        echo "Error: Failed to build the image."
        exit 1
    fi
    echo "Image built successfully."
fi

# Check if the container is already running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container ${CONTAINER_NAME} already exists. Stopping and removing it..."
    docker stop ${CONTAINER_NAME}
    docker rm ${CONTAINER_NAME}
fi

# Run the container
echo "Starting container ${CONTAINER_NAME}..."
docker run -d --name ${CONTAINER_NAME} -p ${PORT}:${PORT} ${IMAGE_NAME}

if [ $? -eq 0 ]; then
    echo "Container started successfully. The application is accessible at http://localhost:${PORT}"
else
    echo "Error: Failed to start the container."
    exit 1
fi 