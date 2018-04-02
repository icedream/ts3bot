#!/bin/sh

set -ex

# For non-interactive install (dpkg)
export INITRD=no
export DEBIAN_FRONTEND=noninteractive

# Now install all packages we need
apt-get install -y --no-install-recommends \
	ca-certificates \
	blackbox xvfb xdotool \
	pulseaudio pulseaudio-utils \
	cmake python-minimal \
	vlc-nox '^libvlc[0-9]+$' libvlc-dev vlc-plugin-pulse
apt-mark auto \
	cmake \
	python-minimal \
	libvlc-dev

# Configure GUI user, we are going to use the pre-setup "app" user for this
mkdir -p /config
ln -sf /config ~app/.ts3bot

# Install TS3Bot
(
	cd ~app/ts3bot
	npm_config_wcjs_runtime="node" npm_config_wcjs_runtime_version="$(node --version | tr -d 'v')" \
		yarn install --check-files --verbose
	yarn global add --prod --check-files "file:$(pwd)"

	# Copy over configuration for daemons
	cp -a etc/* /etc/
)

# Clean up APT
apt-get autoremove -y --purge
apt-get clean
rm -rf ~app/ts3bot /var/lib/apt/lists/* /tmp/* /var/tmp/*
