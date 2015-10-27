FROM phusion/passenger-nodejs:0.9.17

ENV TS3CLIENT_VERSION 3.0.18.2
ENV TS3BOT_COMMIT 034d12df07697ef487213399558eb4627c304973

ADD setup.sh /
RUN sh /setup.sh

# Copy over configuration for other daemons
COPY etc/ /etc

# Startup configuration
WORKDIR /home/app
ENTRYPOINT [ "/sbin/my_init" ]
