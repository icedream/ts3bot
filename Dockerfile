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

ARG TS3CLIENT_VERSION=3.0.19.4

COPY . /home/app/ts3bot/
RUN cd ~app/ts3bot &&\
	sed -i 's,\r,,g' setup.sh &&\
	sh setup.sh

# Startup configuration
WORKDIR /home/app
USER app
CMD [ "ts3bot", "--ts3-install-path=/home/app/ts3client" ]
