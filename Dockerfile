FROM alpine:3.7 AS ts3client-download

ARG TS3CLIENT_VERSION=3.1.8

# Install TeamSpeak3.
# Original comment that used to be here: temporary non-interactive teamspeak3 install hack, remove before publishing!!
# In fact, it would be nice if we had some lazy handling code for this that just requires the user to provide a "--agree-with-license" once.
ADD "http://teamspeak.gameserver.gamed.de/ts3/releases/${TS3CLIENT_VERSION}/TeamSpeak3-Client-linux_amd64-${TS3CLIENT_VERSION}.run" /ts3client.run
RUN sed -i 's/^MS_PrintLicense$/#MS_PrintLicense/g' /ts3client.run
RUN chmod +x /ts3client.run
RUN /ts3client.run --quiet --target ts3client

###

FROM node:7.10.0

# Install runtime packages
RUN apt-get update &&\
	export INITRD=no &&\
	export DEBIAN_FRONTEND=noninteractive &&\
	apt-get install -y --no-install-recommends \
		ca-certificates \
		blackbox xvfb xdotool \
		pulseaudio pulseaudio-utils \
		vlc-nox '^libvlc[0-9]+$' vlc-plugin-pulse

# Add "app" user
RUN mkdir -p /tmp/empty &&\
	groupadd -g 9999 app &&\
	useradd -d /home/app -l -N -g app -m -k /tmp/empty -u 9999 app &&\
	rmdir /tmp/empty

COPY . /home/app/ts3bot/
RUN cd ~app/ts3bot &&\
	sed -i 's,\r,,g' setup.sh &&\
	sh setup.sh

WORKDIR /home/app
COPY --from=ts3client-download /ts3client/ ./ts3client

# Startup configuration
USER app
CMD [ "ts3bot", "--ts3-install-path=/home/app/ts3client" ]
