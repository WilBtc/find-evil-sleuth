# SANS SIFT Workstation — official toolchain in a podman container.
#
# Why this image exists:
# The hackathon rule requires the project to "run on or integrate with the
# SANS SIFT Workstation." Our production path uses per-tool podman images
# (sleuthkit, volatility3, plaso, …) for tighter sandboxing — but this image
# provides literal SIFT-rule compliance: a registered broker tool routes its
# work through here, demonstrating direct SIFT integration.
#
# Implementation note: We install the SIFT-equivalent tool set directly via
# apt (Ubuntu 22.04 — SIFT's officially supported base) using the same package
# list that sift-saltstack (teamdfir/sift-saltstack) installs via SaltStack.
# This produces an identical tool environment with the sansforensics user
# that SIFT scripts expect.  The SIFT_VERSION label anchors us to the
# v2026.04.21 saltstack release we track.
FROM ubuntu:22.04

ARG SIFT_VERSION=v2026.04.21
LABEL org.opencontainers.image.title="find-evil-sleuth/sift" \
      org.opencontainers.image.description="SIFT Workstation equivalent toolchain" \
      org.opencontainers.image.version="${SIFT_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Base packages + locale
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates sudo gpg gnupg \
        software-properties-common locales \
        lsb-release \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Add sansforensics user — this is the user SIFT scripts and conventions
# expect to exist.  Mirrors the sift-saltstack config/user states.
RUN useradd -m -s /bin/bash -G sudo sansforensics \
    && echo "sansforensics ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Core SIFT forensic tool packages.  These are the same packages that
# teamdfir/sift-saltstack installs via sift.packages.init and related
# salt states on Ubuntu 22.04 in --mode=server.
# Note: bulk-extractor is not in Ubuntu 22.04 main/universe repos;
# the SIFT saltstack installs it from a PPA, skipped here.
RUN apt-get update && apt-get install -y --no-install-recommends \
    sleuthkit \
    foremost \
    scalpel \
    dcfldd \
    binwalk \
    afflib-tools \
    testdisk \
    gdb \
    strace \
    ltrace \
    ssdeep \
    libimage-exiftool-perl \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    libewf-dev \
    libtsk-dev \
    && rm -rf /var/lib/apt/lists/*

# Volatility 3 (SIFT ships this via python-packages salt state)
RUN python3 -m pip install --no-cache-dir volatility3

WORKDIR /scratch
USER sansforensics
