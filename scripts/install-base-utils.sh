#!/bin/bash
# General CLI utilities and build tools for the base image.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
    sudo \
    curl \
    wget \
    gnupg \
    ca-certificates \
    git \
    less \
    unzip \
    zip \
    bzip2 \
    xz-utils \
    procps \
    pinentry-curses \
    bc \
    diffutils \
    findutils \
    rsync \
    passwd \
    util-linux \
    lsof \
    tree \
    man-db \
    manpages \
    locales \
    bash-completion \
    openssh-client \
    iputils-ping \
    hostname \
    time \
    xauth \
    pigz \
    vim-tiny \
    nano \
    jq \
    build-essential \
    python3

# Locale for tools that expect UTF-8
sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
locale-gen

apt-get clean
rm -rf /var/lib/apt/lists/*
