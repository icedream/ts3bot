FROM phusion/passenger-nodejs:0.9.17

# get rid of useless services
RUN rm -r /etc/service/cron /etc/service/nginx /etc/service/nginx-log-forwarder

# prepare APT with only the repositories we want
RUN rm /etc/apt/sources.list.d/* &&\
	add-apt-repository ppa:mc3man/trusty-media -y &&\
	DEBIAN_FRONTEND=noninteractive curl -sL https://deb.nodesource.com/setup_4.x | bash - &&\
	DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
		nodejs \
		blackbox xvfb xdotool \
		pulseaudio pulseaudio-utils \
		dbus \
		python python-minimal python-pkg-resources rtmpdump ffmpeg \
		vlc vlc-plugin-pulse

# initialize DBus
RUN mkdir -p /var/run/dbus && \
	chown messagebus:messagebus /var/run/dbus && \
	dbus-uuidgen --ensure

# configure gui user
RUN mkdir -p /config &&\
	ln -sf /config ~app/.ts3bot

# install teamspeak3
# Original comment that used to be here: temporary non-interactive teamspeak3 install hack, remove before publishing!!
# In fact, it would be nice if we had some lazy handling code for this that just requires the user to provide a "--agree-with-license" once.
ENV TS3CLIENT_VERSION 3.0.18.1
ADD http://dl.4players.de/ts/releases/${TS3CLIENT_VERSION}/TeamSpeak3-Client-linux_amd64-${TS3CLIENT_VERSION}.run /home/app/ts3client.run
WORKDIR /home/app
RUN chmod +x ./ts3client.run &&\
	sed -i 's/^MS_PrintLicense$/#MS_PrintLicense/g' ./ts3client.run &&\
	./ts3client.run --quiet --target ts3client &&\
	rm ./ts3client.run
USER root

# install the ts3bot-control app properly
ENV TS3BOT_COMMIT e0379895d77c17a7eac1bd36b7b819f34b102970
ADD https://github.com/icedream/ts3bot-control/archive/${TS3BOT_COMMIT}.tar.gz /home/app/ts3bot-control.tgz
WORKDIR /home/app
RUN tar xvf ts3bot-control.tgz &&\
	rm ts3bot-control.tgz &&\
	mv ts3bot-control* ts3bot
WORKDIR /home/app/ts3bot
RUN npm install

# install youtube-dl
ADD https://yt-dl.org/latest/youtube-dl /usr/local/bin/youtube-dl
RUN chmod a+rx /usr/local/bin/youtube-dl

# initialize other configuration for daemons
COPY etc/ /etc

# clean up apt
RUN apt-get clean && \
	rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

VOLUME [ "/home/app/ts3client" ]

WORKDIR /home/app
ENTRYPOINT [ "/sbin/my_init" ]
