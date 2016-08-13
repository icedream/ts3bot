#!/bin/sh

set -ex

# For non-interactive install (dpkg)
export INITRD=no
export DEBIAN_FRONTEND=noninteractive

# Now install all packages we need
apt-get update
apt-get install -y --no-install-recommends \
	ca-certificates \
	blackbox xvfb xdotool \
	pulseaudio pulseaudio-utils \
	cmake python-minimal \
	vlc-nox '^libvlc[0-9]+$' libvlc-dev vlc-plugin-pulse

# Configure GUI user, we are going to use the pre-setup "app" user for this
mkdir -p /config
ln -sf /config ~app/.ts3bot

# Install TeamSpeak3.
# Original comment that used to be here: temporary non-interactive teamspeak3 install hack, remove before publishing!!
# In fact, it would be nice if we had some lazy handling code for this that just requires the user to provide a "--agree-with-license" once.
cd ~app
wget "http://teamspeak.gameserver.gamed.de/ts3/releases/${TS3CLIENT_VERSION}/TeamSpeak3-Client-linux_amd64-${TS3CLIENT_VERSION}.run" -Ots3client.run
chmod +x ./ts3client.run
sed -i 's/^MS_PrintLicense$/#MS_PrintLicense/g' ./ts3client.run
./ts3client.run --quiet --target ts3client
rm ./ts3client.run

# Install TS3Bot via Git
npm_config_wcjs_runtime="node" npm_config_wcjs_runtime_version="$(node --version | tr -d 'v')" \
	npm link --unsafe-perm ~app/src

# Replace the shipped youtube-dl with the latest version (this is a hack that will hopefully be fixed soon!)
wget -O/usr/local/bin/youtube-dl "https://yt-dl.org/downloads/latest/youtube-dl"
rm -f "$(dirname "$(readlink -f "$(which ts3bot)")")/node_modules/youtube-dl/bin/youtube-dl"
ln -sf "/usr/local/bin/youtube-dl" "$(dirname "$(readlink -f "$(which ts3bot)")")/node_modules/youtube-dl/bin/youtube-dl"
chmod a+rx "/usr/local/bin/youtube-dl"

# Clean up APT
apt-get autoremove -y --purge wget cmake cmake-data
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
