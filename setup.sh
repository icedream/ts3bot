#!/bin/sh

set -ex

# For non-interactive install (dpkg)
export INITRD=no
export DEBIAN_FRONTEND=noninteractive

# Get rid of some preinstalled services we don't need
rm -r /etc/service/cron /etc/service/nginx /etc/service/nginx-log-forwarder

# Set up APT sources
rm /etc/apt/sources.list.d/*
add-apt-repository ppa:mc3man/trusty-media -y
curl -sL https://deb.nodesource.com/setup_4.x | bash -

# Now install all packages we need
apt-get install -y --no-install-recommends \
	nodejs wget ca-certificates \
	blackbox xvfb xdotool \
	pulseaudio pulseaudio-utils \
	dbus \
	python python-minimal python-pkg-resources rtmpdump ffmpeg \
	vlc vlc-plugin-pulse

# DBus initialization
mkdir -p /var/run/dbus
chown messagebus:messagebus /var/run/dbus
dbus-uuidgen --ensure

# Configure GUI user, we are going to use the pre-setup "app" user for this
mkdir -p /config
/sbin/setuser app ln -sf /config ~app/.ts3bot

# Install TeamSpeak3.
# Original comment that used to be here: temporary non-interactive teamspeak3 install hack, remove before publishing!!
# In fact, it would be nice if we had some lazy handling code for this that just requires the user to provide a "--agree-with-license" once.
cd ~app
/sbin/setuser app wget http://dl.4players.de/ts/releases/${TS3CLIENT_VERSION}/TeamSpeak3-Client-linux_amd64-${TS3CLIENT_VERSION}.run -Ots3client.run
chmod +x ./ts3client.run
sed -i 's/^MS_PrintLicense$/#MS_PrintLicense/g' ./ts3client.run
/sbin/setuser app ./ts3client.run --quiet --target ts3client
rm ./ts3client.run

# Install TS3Bot
wget https://github.com/icedream/ts3bot-control/archive/${TS3BOT_COMMIT}.tar.gz -Ots3bot-control.tgz
/sbin/setuser app tar xvf ts3bot-control.tgz
rm ts3bot-control.tgz
mv ts3bot-control* ts3bot
(cd ts3bot && /sbin/setuser app npm install)

# Install youtube-dl (actually done by npm already in a non-system-wide way)
#ADD https://yt-dl.org/latest/youtube-dl /usr/local/bin/youtube-dl
#RUN chmod a+rx /usr/local/bin/youtube-dl

# Clean up APT
apt-get autoremove --purge wget
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
