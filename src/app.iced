Sync = require "sync"

config = require("./config")
getLogger = require("./logger")
services = require("./services")
sync = require "sync"
request = require "request"
fs = require("fs")
path = require("path")
qs = require "querystring"
temp = require("temp").track()
youtubedl = require "youtube-dl"
isValidUrl = (require "valid-url").isWebUri
parseDuration = require "./parse_duration.iced"
prettyMs = require "pretty-ms"

log = getLogger "Main"

# http://stackoverflow.com/a/7117336
removeBB = (str) -> str.replace /\[(\w+)[^\]]*](.*?)\[\/\1]/g, "$2"

module.exports =
	shutdown: (cb) =>
		ts3clientService = services.find("ts3client")
		if ts3clientService and ts3clientService.state == "started"
			await ts3clientService.stop defer(err)
			if err
				cb? new Error "Could not stop TeamSpeak3"
				return

		log.debug "Shutting down services..."
		await services.shutdown defer(err)
		if err
			cb? new Error "Error while shutting down rest of services."
		log.debug "Services shut down."

		cb?()
	shutdownSync: => Sync @shutdown

# Separate our own PulseAudio from any system one by using our own custom XDG directories.
process.env.XDG_RUNTIME_DIR = temp.mkdirSync "ts3bot-xdg"

# Xorg for isolated graphical interfaces!
xorgService = services.find("xorg")
await xorgService.start defer err, vlc
if err
	if not process.env.DISPLAY? or process.env.DISPLAY.trim() == ""
		log.error "X server could not start up and no display is available!", err
		await module.exports.shutdown defer()
		process.exit 1
	log.warn "X server could not start up - will use existing display!", err

# PulseAudio daemon
await services.find("pulseaudio").start defer err
if err
	log.warn "PulseAudio could not start up, audio may not act as expected!", err

# VLC via WebChimera.js
vlcService = services.find("vlc")
await vlcService.start defer err, vlc
if err
	log.warn "VLC could not start up!", err
	await module.exports.shutdown defer()
	process.exit 1

# This is where we keep track of the volume
vlcVolume = 50

# Cached information for tracks in playlist
vlcMediaInfo = {}

# TeamSpeak3
ts3clientService = services.find("ts3client")

ts3clientService.on "started", (ts3proc) =>
	ts3query = ts3clientService.query

	ts3clientService.once "stopped", () =>
		ts3query = undefined

	# VLC event handling
	vlc.onPlaying = () =>
		try
			# TODO: Check why info is sometimes null, something must be wrong with the "add"/"play" commands here!
			# TODO: Do not format as URL in text message if MRL points to local file

			item = vlc.playlist.items[vlc.playlist.currentItem]
			info = vlcMediaInfo[item.mrl]
			url = info?.originalUrl or item.mrl
			title = info?.title or item.mrl
			ts3query?.sendtextmessage 2, 0, "Now playing [URL=#{url}]#{title}[/URL]."

			# Restore audio volume
			vlc.audio.volume = vlcVolume
		catch e
			log.warn "Error in VLC onPlaying handler", e

	vlc.onPaused = () => ts3query?.sendtextmessage 2, 0, "Paused."
	vlc.onForward = () => ts3query?.sendtextmessage 2, 0, "Fast-forwarding..."
	vlc.onBackward = () => ts3query?.sendtextmessage 2, 0, "Rewinding..."
	vlc.onEncounteredError = () => log.error "VLC has encountered an error! You will need to restart the bot.", arguments
	vlc.onStopped = () => ts3query?.sendtextmessage 2, 0, "Stopped."

	ts3query.currentScHandlerID = 1
	ts3query.mydata = {}

	ts3query.on "open", =>
		log.info "TS3 query now ready."

		attempts = 0
		err = null
		init = true
		while init or err != null
			init = false
			if err
				attempts++
				if attempts == 10
					log.error "Could not register to TeamSpeak3 client events, giving up!"
					break
				else
					log.warn "Could not register to TeamSpeak3 client events!", err
			for eventName in [
				"notifytalkstatuschange"
				"notifyconnectstatuschange"
				"notifytextmessage"
				"notifyclientupdated"
				"notifycliententerview"
				"notifyclientleftview"
				"notifyclientchatclosed"
				"notifyclientchatcomposing"
				"notifyclientchannelgroupchanged"
				"notifyclientmoved"
			]
				await ts3query.clientnotifyregister ts3query.currentScHandlerID, eventName, defer(err)
				if err
					break

	ts3query.on "message.selected", (args) =>
		if args["schandlerid"]
			ts3query.currentScHandlerID = parseInt args["schandlerid"]

	ts3query.on "message.notifytalkstatuschange", (args) =>
		await ts3query.use args.schandlerid, defer(err, data)

	ts3query.on "message.notifyconnectstatuschange", (args) =>
		await ts3query.use args.schandlerid, defer(err, data)

		if args.status == "disconnected" and ts3clientService.state != "stopping"
			log.warn "Disconnected from TeamSpeak server, reconnecting in a few seconds..."
			ts3clientService.stopSync()
			setTimeout (() => ts3clientService.restartSync()), 8000

		if args.status == "connecting"
			log.info "Connecting to TeamSpeak server..."

		if args.status == "connection_established"
			log.info "Connected to TeamSpeak server."

	ts3query.on "message.notifyclientupdated", (args) =>
		await ts3query.use args.schandlerid, defer(err, data)
		await ts3query.whoami defer(err, data)
		if not err
			ts3query.mydata = data

	ts3query.on "message.notifytextmessage", (args) =>
		await ts3query.use args.schandlerid, defer(err, data)

		if not args.msg?
			return

		msg = args.msg
		invoker = { name: args.invokername, uid: args.invokeruid, id: args.invokerid }
		targetmode = args.targetmode # 1 = private, 2 = channel

		log.info "<#{invoker.name}> #{msg}"

		# cheap argument parsing here
		firstSpacePos = msg.indexOf " "
		if firstSpacePos == 0
			return
		if firstSpacePos > 0
			name = msg.substring 0, firstSpacePos
			paramline = msg.substring firstSpacePos + 1
			params = paramline.match(/'[^']*'|"[^"]*"|[^ ]+/g) || [];
		else
			name = msg
			paramline = ""
			params = []

		switch name.toLowerCase()
			when "current"
				item = vlc.playlist.items[vlc.playlist.currentItem]
				if not item?
					ts3query?.sendtextmessage args.targetmode, invoker.id, "Not playing anything at the moment."
					return

				info = vlcMediaInfo[item.mrl]
				url = info?.originalUrl or item.mrl
				title = info?.title or item.mrl
				ts3query?.sendtextmessage args.targetmode, invoker.id, "Currently playing [URL=#{url}]#{title}[/URL]."

				# Restore audio volume
				vlc.audio.volume = vlcVolume
			when "pause"
				# now we can toggle-pause playback this easily! yay!
				vlc.togglePause()
				return
			when "play"
				inputBB = paramline.trim()
				input = (removeBB paramline).trim()

				# we gonna interpret play without a url as an attempt to unpause the current song
				if input.length <= 0
					vlc.play()
					return

				# only allow playback from file if it's a preconfigured alias
				if isValidUrl input
					log.debug "Got input URL:", input
				else
					input = config.get "aliases:#{input}"
					if not(isValidUrl input) and not(fs.existsSync input)
						log.debug "Got neither valid URL nor valid alias:", input
						ts3query.sendtextmessage args.targetmode, invoker.id, "Sorry, you're not allowed to play #{inputBB} via the bot."
						return

				# TODO: permission system to check if uid is allowed to play this url or alias

				vlc.playlist.clear()

				# let's give youtube-dl a shot!
				await youtubedl.getInfo input, [
					"--format=bestaudio"
				], defer(err, info)
				if err or not info?
					log.debug "There is no audio-only download for #{inputBB}, downloading full video instead."
					await youtubedl.getInfo input, [
						"--format=best"
					], defer(err, info)
				if err or not info?
					info =
						url: input
				if not info.url?
					info.url = input
					info.title = input # URL as title
				info.originalUrl = input
				vlcMediaInfo[info.url] = info

				# play it in VLC
				vlc.play info.url
			when "time", "seek", "pos", "position"
				inputBB = paramline.trim()
				input = (removeBB paramline).trim()

				# we gonna interpret no argument as us needing to return the current position
				if input.length <= 0
					ts3query.sendtextmessage args.targetmode, invoker.id, "Currently position is #{prettyMs vlc.input.time}."
					return

				ts3query.sendtextmessage args.targetmode, invoker.id, "Seeking to #{prettyMs vlc.input.time}."
				vlc.input.time = parseDuration input

				return
			when "stop-after"
				vlc.playlist.mode = vlc.playlist.Single
				ts3query.sendtextmessage args.targetmode, invoker.id, "Playback will stop after the current playlist item."
			when "loop"
				inputBB = paramline
				input = null
				switch (removeBB paramline).toLowerCase().trim()
					when ""
						# just show current mode
						ts3query.sendtextmessage args.targetmode, invoker.id, "Playlist looping is #{if vlc.playlist.mode == vlc.playlist.Loop then "on" else "off"}."
					when "on"
						# enable looping
						vlc.playlist.mode = vlc.playlist.Loop
						ts3query.sendtextmessage args.targetmode, invoker.id, "Playlist looping is now on."
					when "off"
						# disable looping
						vlc.playlist.mode = vlc.playlist.Normal
						ts3query.sendtextmessage args.targetmode, invoker.id, "Playlist looping is now off."
					else
						ts3query.sendtextmessage args.targetmode, invoker.id, "[B]#{name} on|off[/B] - Turns playlist looping on or off"
						return
			when "next"
				if vlc.playlist.items.count == 0
					ts3query.sendtextmessage args.targetmode, invoker.id, "The playlist is empty."
					return
				if vlc.playlist.mode != vlc.playlist.Loop and vlc.playlist.currentItem == vlc.playlist.items.count - 1
					ts3query.sendtextmessage args.targetmode, invoker.id, "Can't jump to next playlist item, this is the last one!"
					return
				vlc.playlist.next()
			when "prev", "previous"
				if vlc.playlist.items.count == 0
					ts3query.sendtextmessage args.targetmode, invoker.id, "The playlist is empty."
					return
				if vlc.playlist.mode != vlc.playlist.Loop and vlc.playlist.currentItem <= 0
					ts3query.sendtextmessage args.targetmode, invoker.id, "Can't jump to previous playlist item, this is the first one!"
					return
				vlc.playlist.prev()
			when "empty", "clear"
				vlc.playlist.clear()
				ts3query.sendtextmessage args.targetmode, invoker.id, "Cleared the playlist."
			when "enqueue", "add", "append"
				inputBB = paramline.trim()
				input = (removeBB paramline).trim()

				if inputBB.length <= 0
					ts3query.sendtextmessage args.targetmode, invoker.id, "[B]#{name} <url>[/B] - Adds the specified URL to the current playlist"
					return

				# only allow playback from file if it's a preconfigured alias
				if isValidUrl input
					log.debug "Got input URL:", input
				else
					input = config.get "aliases:#{input}"
					if not(isValidUrl input) and not(fs.existsSync input)
						log.debug "Got neither valid URL nor valid alias:", input
						ts3query.sendtextmessage args.targetmode, invoker.id, "Sorry, you're not allowed to play #{inputBB} via the bot."
						return

				# TODO: permission system to check if uid is allowed to play this url or alias

				# let's give youtube-dl a shot!
				await youtubedl.getInfo input, [
					"--format=bestaudio"
				], defer(err, info)
				if err or not info?
					log.debug "There is no audio-only download for #{inputBB}, downloading full video instead."
					await youtubedl.getInfo input, [
						"--format=best"
					], defer(err, info)
				if err or not info?
					info =
						url: input
				if not info.url?
					info.url = input
					info.title = input # URL as title
				info.originalUrl = input
				vlcMediaInfo[info.url] = info

				# add it in VLC
				vlc.playlist.add info.url
				ts3query.sendtextmessage args.targetmode, invoker.id, "Added [URL=#{input}]#{info.title}[/URL] to the playlist."

				# TODO: Do we need to make sure that vlc.playlist.mode is not set to "Single" here or is that handled automatically?
			when "stop"
				vlc.stop()
			when "vol"
				inputBB = paramline.trim()
				input = (removeBB paramline).trim()

				if inputBB.length <= 0
					ts3query.sendtextmessage args.targetmode, invoker.id, "Volume is currently set to #{vlcVolume}%."
					return

				vol = parseInt input

				if paramline.trim().length <= 0 or isNaN(vol) or vol > 200 or vol < 0
					ts3query.sendtextmessage args.targetmode, invoker.id, "[B]vol <number>[/B] - takes a number between 0 (0%) and 200 (200%) to set the volume. 100% is 100. Defaults to 50 (50%) on startup."
					return

				vlc.audio.volume = vlcVolume = vol
				ts3query.sendtextmessage args.targetmode, invoker.id, "Volume set to #{vol}%."
			when "changenick"
				nick = paramline
				Sync () =>
					try
						ts3query.clientupdate.sync ts3query, { client_nickname: nick }
					catch err
						log.warn "ChangeNick failed, error information:", err
						switch err.id
							when 513 then ts3query.sendtextmessage args.targetmode, invoker.id, "That nickname is already in use."
							when 1541 then ts3query.sendtextmessage args.targetmode, invoker.id, "That nickname is too short or too long."
							else ts3query.sendtextmessage args.targetmode, invoker.id, "That unfortunately didn't work out."

await ts3clientService.start [ config.get("ts3-server") ], defer(err, ts3proc)
if err
	log.error "TeamSpeak3 could not start, shutting down.", err
	await module.exports.shutdown defer()
	process.exit 1
