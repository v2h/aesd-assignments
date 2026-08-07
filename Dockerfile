FROM ubuntu:22.04

# Avoid interactive tzdata/apt prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Toolchain needed to build and run the AESD assignment scripts and unit tests:
#   build-essential  -> gcc, make (compile the Unity C tests)
#   cmake            -> configure the test build (22.04 provides 3.22, >= 3.5)
#   ruby             -> Unity's auto_generate.sh generates the test runners
#   git              -> submodule operations
#   grep/findutils   -> used by finder.sh / writer.sh (present, listed for clarity)
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ruby \
        git \
        grep \
        findutils \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user matching the host user's UID/GID. This makes files
# written to the mounted repo (build/, logs) owned by you instead of root, and
# gives the shell a real user name + $HOME instead of "I have no name!".
# docker-run.sh passes your host UID/GID via --build-arg.
ARG USER_NAME=aesd
ARG USER_UID=1000
ARG USER_GID=1000
RUN if ! getent group "${USER_GID}" >/dev/null; then \
        groupadd -g "${USER_GID}" "${USER_NAME}"; \
    fi \
 && useradd -m -u "${USER_UID}" -g "${USER_GID}" -s /bin/bash "${USER_NAME}"

# Avoid git "dubious ownership" errors on the bind-mounted repo (all users).
RUN git config --system --add safe.directory /work \
 && git config --system --add safe.directory /work/assignment-autotest

USER ${USER_NAME}
WORKDIR /work

CMD ["/bin/bash"]
