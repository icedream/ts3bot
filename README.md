# TS3Bot

A new and easy way to set up your own TeamSpeak 3 bot!

*This is currently still a project in early development, it basically works just fine as long as you don't try to do anything out of the ordinary to it. Let me know via the issue tracker if you find problems, errors or if you have questions!*

## Supported features

- Thanks to youtube-dl support for YouTube, SoundCloud, hundreds of other media portals and direct livestreams
- Change the volume on the bot on the fly
- Playlisting system (you can currently enqueue tracks, skip tracks and loop them)
- Takes commands from both channel and private messages
- Can change nickname on the fly

## Supported commands

- `changenick <nickname>` - Changes the bot's nickname.
- `clear` or `empty` - Empties the current playlist.
- `current` - Shows the currently playing track in the chat.
- `enqueue <url>` or `add <url>` or `append <url>` - Adds a URL to the playlist.
- `loop on` or `loop off` - Enables or disables playlist looping.
- `next` - Jumps to the next item in the playlist.
- `pause` - Pause playback of the current track.
- `play` - Resumes playback of the current track.
- `play <url>` - Plays a URL.
- `prev` or `previous` - Jumps to the previous item in the playlist.
- `stop` - Stops playback immediately.
- `stop-after` - Stops playback after the current item is done playing.
- `vol <value>` - Changes the playback volume, value can be between 0 (for 0%) and 200 (for 200%). Default at startup is 50 (50%).

## Running TS3Bot

### With Docker

The Docker image contains everything necessary to run Icedream's TS3Bot. You only need to provide a configuration with an identity and off it goes!

1. You can pull the latest image via `docker pull icedream/ts3bot`.
2. Create a folder, it will contain your configuration and your identity file that the bot uses to log in.
3. Create a `config.json` in the configuration folder. A working example would be here:
   
    ```json
    {
      "identity-path": "/config/identity.ini",
      "ts3-server": "ts3server://<your.ts3.server>?port=<port>&password=<password>&channel=<channelpath>"
    }
    ```
   
    Note that you can generate the URL for `ts3-server` using your TS3 client via Extras > Invite friend, select the checkbox "Channel" and select "ts3server link" as invitation type.
4. Generate an identity in your TeamSpeak3 client (Settings > Identities > Add), set the nickname to the nickname you want the bot to have and optionally increase the security level to the level needed for your bot to join the server.
5. Export the identity you just generated via the "Export" button. Save it as `identity.ini` and put it into your configuration folder from earlier. You can now delete the identity from your TS3 client.
6. Now set up a container with your configuration folder mounted at `/config`. The command for this would be: `docker run -d -v "<path to your config folder>:/config:ro" icedream/ts3bot`

Alternatively instead of running a `docker` command you can use [Docker Compose](https://docs.docker.com/compose/). A typical `docker-compose.yml` for this would be:

```yaml
bot:
  image: icedream/ts3bot
  volume:
  - "<path to your config folder>:/config:ro"
```

### Without Docker

Basically these instructions are derived from [the Docker build files](https://github.com/icedream/ts3bot-docker).
You can adopt these depending on your OS (the Docker image uses Debian Jessie, so the instructions below are for that OS).

We assume that we want to run the "develop" branch of TS3Bot here. You can easily replace "develop" with another branch you want to run, like "master" for the stable code.

We create a separate user "ts3bot" for this bot using the command below - do not run this on your own user if you use TeamSpeak3 on it as the bot will overwrite the configuration of the client later!

        # adduser --disabled-login --disabled-password ts3bot

And we access the user's shell usually via:

        # sudo -u ts3bot -s -H

Commands being run as your bot user (`ts3bot`) are marked with `$` and commands being run as root are marked with `#`.

- Install the dependencies, optionally add `git` if you are going to use the git client for cloning the source code later:

        # apt-get install node-dev blackbox xvfb xdotool pulseaudio pulseaudio-utils cmake libvlc-dev vlc-plugin-pulse

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

## Planned features

- Web interface
- Timestamping/skip intros (ts3bot-control issue [#3](https://github.com/icedream/ts3bot-control/issues/3))
- Volume adjustment (ts3bot-control issue [#5](https://github.com/icedream/ts3bot-control/issues/5))
- Playlisting (ts3bot-control issue [#2](https://github.com/icedream/ts3bot-control/issues/2))
- Permission system (ts3bot-control issue [#1](https://github.com/icedream/ts3bot-control/issues/1))
- Command aliases to quickly reuse media
- Show currently playing media metadata (ts3bot-control issue [#7](https://github.com/icedream/ts3bot-control/issues/7))
- Recording features
