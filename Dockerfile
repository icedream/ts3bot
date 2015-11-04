FROM node:4.2

ENV TS3CLIENT_VERSION 3.0.18.2
ENV TS3BOT_COMMIT 655659e254940082a3629631fbf8e698bf4689da

# Add "app" user
RUN mkdir -p /tmp/empty &&\
	groupadd -g 9999 app &&\
	useradd -d /home/app -l -N -g app -m -k /tmp/empty -u 9999 app &&\
	rmdir /tmp/empty

ADD setup.sh /
RUN sh /setup.sh

# Pass through process nice caps for pulseaudio
RUN setcap 'cap_sys_nice=ep' $(which pulseaudio)

# Copy over configuration for other daemons
COPY etc/ /etc

# Startup configuration
WORKDIR /home/app
USER app
CMD [ "node", "/home/app/ts3bot", "--ts3-install-path=/home/app/ts3client" ]
