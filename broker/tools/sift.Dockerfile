# SANS SIFT Workstation — official toolchain in a podman container.
#
# Why this image exists:
# The hackathon rule requires the project to "run on or integrate with the
# SANS SIFT Workstation." Our production path uses per-tool podman images
# (sleuthkit, volatility3, plaso, …) for tighter sandboxing — but this image
# provides literal SIFT-rule compliance: a registered broker tool routes its
# work through here, demonstrating direct SIFT integration.
#
# Built using teamdfir/sift-cli against Ubuntu 22.04 (SIFT's officially
# supported base). ~10 GB on disk, ~30 min to build first time.
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates sudo gpg \
        software-properties-common locales \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Add a non-root sansforensics user the SIFT installer expects.
RUN useradd -m -s /bin/bash -G sudo sansforensics \
    && echo "sansforensics ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Pull sift-cli (server mode = headless, what we want for a tool sandbox).
ARG SIFT_CLI_VERSION=v1.14.0-rc1
RUN curl -fsSL -o /usr/local/bin/sift-cli \
        "https://github.com/teamdfir/sift-cli/releases/download/${SIFT_CLI_VERSION}/sift-cli-linux" \
    && chmod +x /usr/local/bin/sift-cli

# Headless server install. Fails closed; we want the build to fail if SIFT
# install errors out (vs silently producing an empty image).
USER sansforensics
RUN sudo sift-cli install --mode=server -y || \
    (echo "SIFT install failed — see above" && exit 1)

WORKDIR /scratch
USER sansforensics
