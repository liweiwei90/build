#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Host packages for CI / Ubuntu 24.04 runners. Keep in sync with docker/Dockerfile.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
	bc bison build-essential bzip2 ca-certificates ccache chrpath cpio curl \
	device-tree-compiler diffstat dosfstools e2fsprogs fakeroot file flex \
	g++-aarch64-linux-gnu gcc-aarch64-linux-gnu gawk genimage git \
	kmod libgnutls28-dev libssl-dev locales lz4 make mtools patch perl python3 \
	python3-cryptography python3-dev python3-jinja2 python3-pyelftools \
	python3-setuptools rpcsvc-proto rsync socat swig texinfo \
	u-boot-tools unzip wget xz-utils zstd
