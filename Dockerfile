FROM node:4.2

ENV TS3CLIENT_VERSION 3.0.18.2
ENV TS3BOT_COMMIT 2e246a1a9888bd9318dbb3f5c9f800e0c964c330

# Add "app" user
RUN mkdir -p /tmp/empty &&\
	groupadd -g 9999 app &&\
	useradd -d /home/app -l -N -g app -m -k /tmp/empty -u 9999 app &&\
	rmdir /tmp/empty

ADD setup.sh /
RUN sh /setup.sh

# Copy over configuration for other daemons
COPY etc/ /etc

# Startup configuration
WORKDIR /home/app
USER app
CMD [ "node", "/home/app/ts3bot", "--ts3-install-path=/home/app/ts3client" ]
