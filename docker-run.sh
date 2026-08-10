#!/bin/bash
# Run the AESD assignment scripts inside the ubuntu:22.04 dev container
# so nothing needs to be installed on the host.
#
# This uses ONE long-lived, named container so anything written inside it
# (e.g. a kernel/busybox build under /tmp/aeld) survives between invocations.
# The container is created once, kept alive with `sleep infinity`, started if
# stopped, and re-entered with `docker exec` on every run.
#
# Usage:
#   ./docker-run.sh                 # open an interactive shell in the container
#   ./docker-run.sh ./unit-test.sh  # run a single command inside the container
#   ./docker-run.sh ./full-test.sh
#   ./docker-run.sh --clean         # stop & remove the container (frees its data)
set -e

IMAGE=aesd-dev
CONTAINER=aesd-dev-container        # the persistent, named container

# Always run from the repo root (the directory this script lives in)
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DOCKERFILE="$REPO_DIR/Dockerfile"

# Host user identity, baked into the image and used to run the container
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# --- cleanup option: remove the container this script manages, then exit ---
# Scoped to our named container only -- it will NOT touch your other containers.
# The image is left in place (it's cheap to keep; rebuilds are cached).
if [ "${1:-}" = "--clean" ] || [ "${1:-}" = "clean" ]; then
    if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
        echo "Removing container '$CONTAINER' (and its build data)..."
        docker rm -f "$CONTAINER" >/dev/null
        echo "Done."
    else
        echo "No container named '$CONTAINER' exists; nothing to clean."
    fi
    exit 0
fi

# Fingerprint of the build inputs. Includes the Dockerfile contents and the
# build-args, so any change to either triggers a rebuild below. Stored on the
# image as a label so we can compare without keeping a separate state file.
BUILD_FINGERPRINT="$(
    { cat "$DOCKERFILE"; echo "USER_UID=$HOST_UID USER_GID=$HOST_GID"; } | sha256sum | cut -d' ' -f1
)"

build_image() {
    echo "Building image '$IMAGE' ($1)..."
    docker build \
        --build-arg USER_UID="$HOST_UID" \
        --build-arg USER_GID="$HOST_GID" \
        --label "aesd.build.fingerprint=$BUILD_FINGERPRINT" \
        -t "$IMAGE" "$REPO_DIR"
    # The existing container was created from the OLD image; drop it so a fresh
    # one is created below from the newly built image.
    if docker container inspect "$CONTAINER" >/dev/null 2>&1; then
        echo "Removing stale container '$CONTAINER' (image changed)..."
        docker rm -f "$CONTAINER" >/dev/null
    fi
}

# Build the image on first run (or if it was removed), and rebuild whenever the
# Dockerfile or build-args have changed since the image was last built. Bake in
# the host user's UID/GID so the in-container user matches you (clean prompt +
# correct file ownership on the mounted repo).
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    build_image "image not found"
else
    IMAGE_FINGERPRINT="$(docker image inspect "$IMAGE" \
        --format '{{ index .Config.Labels "aesd.build.fingerprint" }}' 2>/dev/null)"
    if [ "$IMAGE_FINGERPRINT" != "$BUILD_FINGERPRINT" ]; then
        build_image "Dockerfile or build-args changed"
    fi
fi

# Ensure the long-lived container exists and is running.
#   - not present -> create it detached, idling on `sleep infinity`
#   - present but stopped -> start it
# The mount (-v), user (-u) and workdir are fixed at creation time; `docker exec`
# below inherits them.
if ! docker container inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "Creating long-lived container '$CONTAINER'..."
    docker run -d \
        --name "$CONTAINER" \
        -u "$HOST_UID:$HOST_GID" \
        -v "$REPO_DIR":/work \
        -w /work \
        "$IMAGE" sleep infinity >/dev/null
elif [ "$(docker container inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]; then
    echo "Starting existing container '$CONTAINER'..."
    docker start "$CONTAINER" >/dev/null
fi

# Only allocate a TTY when we actually have one (so the script also works
# when its output is piped or run from a non-interactive context).
TTY_FLAGS="-i"
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAGS="-it"
fi

# --- debug: show the values before entering the container ---
echo "----- docker-run.sh debug -----"
echo "IMAGE     = $IMAGE"
echo "CONTAINER = $CONTAINER"
echo "FINGERPRT = $BUILD_FINGERPRINT"
echo "REPO_DIR  = $REPO_DIR"
echo "HOST_UID  = $HOST_UID"
echo "HOST_GID  = $HOST_GID"
echo "TTY_FLAGS = $TTY_FLAGS"
echo "MOUNT     = $REPO_DIR:/work"
echo "COMMAND   = ${*:-<interactive shell>}"
echo "-------------------------------"

# Enter the running container. With no arguments, open an interactive shell;
# otherwise run the given command. -w /work matches the old behaviour.
if [ "$#" -eq 0 ]; then
    docker exec $TTY_FLAGS -w /work "$CONTAINER" /bin/bash
else
    docker exec $TTY_FLAGS -w /work "$CONTAINER" "$@"
fi
