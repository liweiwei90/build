# OpenTina unified build environment (Ubuntu 24.04), aligned with typical host deps
# (gcc-aarch64-linux-gnu, genimage, U-Boot host tools, etc.).
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
	OPENTINA_IN_DOCKER=1 \
	LANG=en_US.UTF-8 \
	LC_ALL=en_US.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
	bc bison build-essential bzip2 ca-certificates ccache chrpath cpio curl \
	device-tree-compiler diffstat dosfstools e2fsprogs fakeroot file flex \
	g++-aarch64-linux-gnu gcc-aarch64-linux-gnu gawk genimage git \
	kmod libgnutls28-dev libssl-dev locales lz4 make mtools patch perl python3 \
	python3-cryptography python3-dev python3-jinja2 python3-pyelftools \
	python3-setuptools rpcsvc-proto rsync socat swig texinfo \
	u-boot-tools unzip wget xz-utils zstd \
	&& sed -i '/^# *en_US.UTF-8 UTF-8/s/^# *//' /etc/locale.gen \
	&& locale-gen en_US.UTF-8 \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
