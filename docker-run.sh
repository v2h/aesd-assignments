#!/bin/bash
# Run the AESD assignment scripts inside the ubuntu:22.04 dev container
# so nothing needs to be installed on the host.
#
# Usage:
#   ./docker-run.sh                 # open an interactive shell in the container
#   ./docker-run.sh ./unit-test.sh  # run a single command, then exit
#   ./docker-run.sh ./full-test.sh
set -e

IMAGE=aesd-dev

# Always run from the repo root (the directory this script lives in)
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# Host user identity, baked into the image and used to run the container
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# Build the image on first run (or if it was removed). Bake in the host user's
# UID/GID so the in-container user matches you (clean prompt + correct file
# ownership on the mounted repo).
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Image '$IMAGE' not found, building it..."
    docker build \
        --build-arg USER_UID="$HOST_UID" \
        --build-arg USER_GID="$HOST_GID" \
        -t "$IMAGE" "$REPO_DIR"
fi

# Only allocate a TTY when we actually have one (so the script also works
# when its output is piped or run from a non-interactive context).
TTY_FLAGS="-i"
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAGS="-it"
fi

# --- debug: show the values before launching the container ---
echo "----- docker-run.sh debug -----"
echo "IMAGE     = $IMAGE"
echo "REPO_DIR  = $REPO_DIR"
echo "HOST_UID  = $HOST_UID"
echo "HOST_GID  = $HOST_GID"
echo "TTY_FLAGS = $TTY_FLAGS"
echo "MOUNT     = $REPO_DIR:/work"
echo "COMMAND   = ${*:-<interactive shell>}"
echo "-------------------------------"

# -u  : run as the host user so files created (build/, logs) are not root-owned
# -v  : bind-mount the repo into /work (edits on the host are seen instantly)
# -w  : start in /work
docker run --rm $TTY_FLAGS \
    -u "$HOST_UID:$HOST_GID" \
    -v "$REPO_DIR":/work \
    -w /work \
    "$IMAGE" "$@"
