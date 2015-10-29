FROM phusion/passenger-nodejs:0.9.17

ENV TS3CLIENT_VERSION 3.0.18.2
ENV TS3BOT_COMMIT c20462272f370ed1e88a5227860583fe3e0559a3

ADD setup.sh /
RUN sh /setup.sh

# Copy over configuration for other daemons
COPY etc/ /etc

# Startup configuration
WORKDIR /home/app
ENTRYPOINT [ "/sbin/my_init" ]
