FROM node:4.2

ENV TS3CLIENT_VERSION 3.0.18.2
ENV TS3BOT_COMMIT 82c19a2196770c463d8c94fc9e5842dfe8697c8d

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
