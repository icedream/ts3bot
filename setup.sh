#!/bin/sh

set -ex

# For non-interactive install (dpkg)
export INITRD=no
export DEBIAN_FRONTEND=noninteractive

# Now install all packages we need
apt-get update
apt-get install -y --no-install-recommends \
	wget ca-certificates \
	blackbox xvfb xdotool \
	pulseaudio pulseaudio-utils \
	cmake cmake-data \
	python python-minimal python-pkg-resources \
	vlc-nox '^libvlc[0-9]+$' libvlc-dev vlc-plugin-pulse

# Configure GUI user, we are going to use the pre-setup "app" user for this
mkdir -p /config
ln -sf /config ~app/.ts3bot

# Install TeamSpeak3.
# Original comment that used to be here: temporary non-interactive teamspeak3 install hack, remove before publishing!!
# In fact, it would be nice if we had some lazy handling code for this that just requires the user to provide a "--agree-with-license" once.
cd ~app
wget http://dl.4players.de/ts/releases/${TS3CLIENT_VERSION}/TeamSpeak3-Client-linux_amd64-${TS3CLIENT_VERSION}.run -Ots3client.run
chmod +x ./ts3client.run
sed -i 's/^MS_PrintLicense$/#MS_PrintLicense/g' ./ts3client.run
./ts3client.run --quiet --target ts3client
rm ./ts3client.run

# Install TS3Bot
wget https://github.com/icedream/ts3bot-control/archive/${TS3BOT_COMMIT}.tar.gz -O- |\
	tar xzv
mv ts3bot-control* ts3bot
(cd ts3bot && \
	npm_config_wcjs_runtime="node" npm_config_wcjs_runtime_version="$(node --version | tr -d 'v')" \
		npm install)

# Install youtube-dl (actually done by npm already in a non-system-wide way)
#ADD https://yt-dl.org/latest/youtube-dl /usr/local/bin/youtube-dl
#RUN chmod a+rx /usr/local/bin/youtube-dl

# Clean up APT
apt-get autoremove -y --purge wget cmake cmake-data
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
