FROM phusion/passenger-nodejs:0.9.17

ENV TS3CLIENT_VERSION 3.0.18.2
ENV TS3BOT_COMMIT 6695fbd83ee07677e6ef920d7687de6a24011d90

ADD setup.sh /
RUN sh /setup.sh

# Copy over configuration for other daemons
COPY etc/ /etc

# Startup configuration
WORKDIR /home/app
ENTRYPOINT [ "/sbin/my_init" ]
