FROM phusion/passenger-nodejs:0.9.17

ENV TS3CLIENT_VERSION 3.0.18.2
ENV TS3BOT_COMMIT ed10e875b3bf07f1ddfc3cca2d324fb64ec6d9ed

ADD setup.sh /
RUN sh /setup.sh

# Copy over configuration for other daemons
COPY etc/ /etc

# Startup configuration
WORKDIR /home/app
ENTRYPOINT [ "/sbin/my_init" ]
