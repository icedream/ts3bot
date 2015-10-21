Sync = require "sync"

config = require("./config")
getLogger = require("./logger")
services = require("./services")
sync = require "sync"
request = require "request"
fs = require("fs")
path = require("path")
qs = require "querystring"
youtubedl = require "youtube-dl"
isValidUrl = (require "valid-url").isWebUri

log = getLogger "Main"

# http://stackoverflow.com/a/7117336
removeBB = (str) -> str.replace /\[(\w+)[^\]]*](.*?)\[\/\1]/g, "$2"

module.exports =
	shutdown: (cb) =>
		apiService = services.find("api")
		if apiService and apiService.state == "started"
			await apiService.stop defer(err)
			if err
				cb? new Error "Could not stop API"
				return

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

# PulseAudio daemon
await services.find("pulseaudio").start defer err
if err
	log.warn "PulseAudio could not start up, audio may not act as expected!"

# VLC HTTP API
await services.find("vlc").start defer err
if err
	log.warn "VLC could not start up!"
	await module.exports.shutdown defer()
	process.exit 1
vlc = services.find("vlc").instance

# TeamSpeak3
ts3clientService = services.find("ts3client")

ts3clientService.on "started", (ts3proc) =>
	ts3query = ts3clientService.query

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
			when "pause"
				vlc.status.pause()
				return
			when "play"
				inputBB = paramline.trim()

				# we gonna interpret play without a url as an attempt to unpause the current song
				if inputBB.length <= 0
					vlc.status.resume()
					return

				input = removeBB inputBB

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

				await vlc.status.empty defer(err)
				if err
					log.warn "Couldn't empty VLC playlist", err
					ts3query.sendtextmessage args.targetmode, invoker.id, "Sorry, an error occurred. Try again later."
					return

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

				await vlc.status.play info.url, defer(err)
				if err
					vlc.status.empty()
					log.warn "VLC API returned an error when trying to play", err
					ts3query.sendtextmessage args.targetmode, invoker.id, "Something seems to be wrong with the specified media. Try checking the URL/path you provided?"
					return

				ts3query.sendtextmessage args.targetmode, invoker.id, "Now playing [URL=#{input}]#{info.title}[/URL]."
			when "next"
				await vlc.status.next defer(err)
				if err
					vlc.status.empty()
					log.warn "VLC API returned an error when trying to skip current song", err
					ts3query.sendtextmessage args.targetmode, invoker.id, "This didn't work. Does the playlist have multiple songs?"
					return

				ts3query.sendtextmessage args.targetmode, invoker.id, "Playing next song in the playlist."
			when "enqueue", "add", "append"
				inputBB = paramline

				if inputBB.length <= 0
					ts3query.sendtextmessage args.targetmode, invoker.id, "[B]#{name} <url>[/B] - Adds the specified URL to the current playlist"
					return

				input = removeBB paramline

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

				await vlc.status.enqueue info.url, defer(err)
				if err
					vlc.status.empty()
					log.warn "VLC API returned an error when trying to play", err
					ts3query.sendtextmessage args.targetmode, invoker.id, "Something seems to be wrong with the specified media. Try checking the URL/path you provided?"
					return

				ts3query.sendtextmessage args.targetmode, invoker.id, "Added [URL=#{input}]#{info.title}[/URL] to the playlist."
			when "stop"
				await vlc.status.stop defer(err)

				vlc.status.empty()

				ts3query.sendtextmessage args.targetmode, invoker.id, "Stopped playback."
			when "vol"
				vol = parseInt paramline

				if paramline.trim().length <= 0 or vol > 511 or vol < 0
					ts3query.sendtextmessage args.targetmode, invoker.id, "[B]vol <number>[/B] - takes a number between 0 (0%) and 1024 (400%) to set the volume. 100% is 256. Defaults to 128 (50%) on startup."
					return

				await vlc.status.volume paramline, defer(err)

				if err
					log.warn "Failed to set volume", err
					ts3query.sendtextmessage args.targetmode, invoker.id, "That unfortunately didn't work out."
					return

				ts3query.sendtextmessage args.targetmode, invoker.id, "Volume set."
			when "changenick"
				nick = if paramline.length > params[0].length then paramline else params[0]
				if nick.length < 1 or nick.length > 32
					ts3query.sendtextmessage args.targetmode, invoker.id, "Invalid nickname."
					return
				Sync () =>
					try
						ts3query.clientupdate.sync ts3query, { client_nickname: nick }
					catch err
						ts3query.sendtextmessage args.targetmode, invoker.id, "That unfortunately didn't work out."
						log.warn "ChangeNick failed, error information:", err

await ts3clientService.start [ config.get("ts3-server") ], defer(err, ts3proc)
if err
	log.error "TeamSpeak3 could not start, shutting down."
	await module.exports.shutdown defer()
	process.exit 1
