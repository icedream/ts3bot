# TS3Bot for Docker

This is the Docker image that contains everything necessary to run Icedream's TS3Bot. You only need to provide a configuration with an identity and off it goes!

## Supported features

- Thanks to VLC support for YouTube and direct livestreams
- Takes commands from both channel and private messages
- Can change nickname on the fly

## Supported commands

- `play <url>` - Plays a URL
- `stop` - Stops playback
- `changenick <nickname>` - Changes the bot's nickname

## How to run this?

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
6. Now set up a container with your configuration folder mounted at `/config`. The command for this would be: `docker run -d -v "<path to your config folder>:/config:ro" --cap-add SYS_NICE icedream/ts3bot`

Alternatively instead of running a `docker` command you can use [Docker Compose](https://docs.docker.com/compose/). A typical `docker-compose.yml` for this would be:

```yaml
bot:
  image: icedream/ts3bot
  volume:
  - "<path to your config folder>:/config:ro"
  cap_add:
  - SYS_NICE
```

## Source code

The main repository for the source code of the bot is available at [https://github.com/icedream/ts3bot-control](https://github.com/icedream/ts3bot-control).

## Planned features

- Improve support for video platforms (see issue [#1](https://github.com/icedream/ts3bot-docker/issues/1) and ts3bot-control issue [#4](https://github.com/icedream/ts3bot-control/issues/4))
- Timestamping/skip intros (ts3bot-control issue [#3](https://github.com/icedream/ts3bot-control/issues/3))
- Volume adjustment (ts3bot-control issue [#5](https://github.com/icedream/ts3bot-control/issues/5))
- Playlisting (ts3bot-control issue [#2](https://github.com/icedream/ts3bot-control/issues/2))
- Permission system (ts3bot-control issue [#1](https://github.com/icedream/ts3bot-control/issues/1))
- Command aliases to quickly reuse media
- Show currently playing media metadata (ts3bot-control issue [#7](https://github.com/icedream/ts3bot-control/issues/7))
- Recording features