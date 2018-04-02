# TS3Bot

A new and easy way to set up your own TeamSpeak 3 bot!

This repository contains the Node.js/IcedCoffeeScript code needed for the TS3Bot Docker image.

## Running TS3Bot without Docker

Basically these instructions are derived from [the Docker build files](https://github.com/icedream/ts3bot-docker).
You can adopt these depending on your OS (the Docker image uses Debian Jessie, so the instructions below are for 
that OS).

We assume that we want to run the "develop" branch of TS3Bot here. You can easily replace "develop" with another branch you want to run, like "master" for the stable code.

We create a separate user "ts3bot" for this bot using the command below - do not run this on your own user if you use TeamSpeak3 on it as the bot will overwrite the configuration of the client later!

        # adduser --disabled-login --disabled-password ts3bot

And we access the user's shell usually via:

        # sudo -u ts3bot -s -H

Commands being run as your bot user (`ts3bot`) are marked with `$` and commands being run as root are marked with `#`.

- Install the dependencies, optionally add `git` if you are going to use the git client for cloning the source code later: 

        # apt-get install node-dev blackbox xorg-server xf86-video-dummy xdotool pulseaudio pulseaudio-utils cmake libvlc-dev vlc-plugin-pulse

- Download and unpack TeamSpeak3 client for your platform into a folder accessible by the TS3Bot user. Only read access is required. Replace `3.0.18.2` with whatever version of TeamSpeak3 you prefer to install, usually that is the most recent one. Accept the license that shows up in the process. Also replace `amd64` with `x86` if you're on a 32-bit system.

        $ cd ~
        $ wget -Ots3client.run http://dl.4players.de/ts/releases/3.0.18.2/TeamSpeak3-Client-linux_amd64-3.0.18.2.run
        $ chmod +x ts3client.run
        $ ./ts3client.run --target ~ts3bot/ts3client
        $ rm ts3client.run

- Download the TS3Bot control application into your TS3Bot user's home folder. The TS3Bot user itself only needs read access to the code. You can do this in two ways:

    o By downloading the tar.gz archive from GitHub and unpacking it.

        $ wget -q -O- https://github.com/icedream/ts3bot-control/archive/develop.tar.gz | tar xz -C ~

    o By cloning the Git repository from GitHub.
    
        $ git clone https://github.com/icedream/ts3bot-control -b develop ~/ts3bot-control-develop
        
- Install the Node.js dependencies using `npm`. Note how a simple `npm install` will install the wrong version of WebChimera.js and you need to provide it with correct Node.js information (environment variables `npm_config_wcjs_runtime` and `npm_config_wcjs_runtime_version`) like this:

        $ cd ~ts3bot/ts3bot-control-develop
        $ npm_config_wcjs_runtime="node" npm_config_wcjs_runtime_version="$(node --version | tr -d 'v')" npm install

- Now set up your TS3Bot configuration files in your TS3Bot user's home folder. For this create a folder `.ts3bot` in the home directory and put a `config.json` with your configuration there. The most minimal configuration consists of:

    o `identity-path` - The path to your identity INI file, export a newly generated identity from your own TeamSpeak3 client for that.

    o `ts3-install-path` - The path where you installed the TeamSpeak3 client to, you can skip this if you used exactly the same path as in the instructions above.

    o `ts3-server` - The URL to the server/channel you want the bot to connect to, you can get from your own TS3 client via "Extras" > "Invite friend", select the checkbox "Channel" and select "ts3server link" as invitation type.

Running the bot can finally be done like this:

    $ node ~/ts3bot-control-develop

You can provide your configuration as command line arguments instead if you want, that can be useful for just temporary configuration you want to test. For that just append the configuration options to the command line above and prefix every command line option with `--`, for example for `ts3-install-path` you would write `--ts3-install-path=/your/path/to/ts3client`
