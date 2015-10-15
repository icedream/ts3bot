Sync = require "sync"

config = require("./config")
getLogger = require("./logger")
services = require("./services")
sync = require "sync"
request = require "request"
fs = require("fs")
path = require("path")
qs = require "querystring"

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
			when "play"
				q =
					uid: invoker.uid
					input: removeBB paramline
				await request "http://127.0.0.1:16444/play?#{qs.stringify q}", defer(err, response)
				switch response.statusCode
					when 200 then ts3query.sendtextmessage args.targetmode, invoker.id, "Now playing #{paramline}."
					when 400 then ts3query.sendtextmessage args.targetmode, invoker.id, "Something seems to be wrong with what you wrote. Maybe check the URL/sound name you provided?"
					when 403 then ts3query.sendtextmessage args.targetmode, invoker.id, "Sorry, you're not allowed to play #{q.input} via the bot."
					else
						log.warn "API reported error", response.statusCode, err
						ts3query.sendtextmessage args.targetmode, invoker.id, "Sorry, an error occurred. Try again later."
			when "stop"
				q =
					uid: invoker.uid
				await request "http://127.0.0.1:16444/stop?#{qs.stringify q}", defer(err, response)
				switch response.statusCode
					when 200 then ts3query.sendtextmessage args.targetmode, invoker.id, "Stopped playback."
					when 403 then ts3query.sendtextmessage args.targetmode, invoker.id, "Sorry, you're not allowed to do that."
					else
						log.warn "API reported error", response.statusCode, err
						ts3query.sendtextmessage args.targetmode, invoker.id, "Sorry, an error occurred. Try again later."
			when "setvolume"
				q =
					uid: invoker.uid
					volume: parseFloat paramline
				await request "http://127.0.0.1:16444/setvolume?#{qs.stringify q}", defer(err, response)
				switch response.statusCode
					when 200 then ts3query.sendtextmessage args.targetmode, invoker.id, "Set volume to #{q.volume}"
					when 400 then ts3query.sendtextmessage args.targetmode, invoker.id, "Something seems to be wrong with what you wrote. Maybe check the volume? It's supposed to be a floating-point number between 0 and 2."
					when 403 then ts3query.sendtextmessage args.targetmode, invoker.id, "Sorry, you're not allowed to do that."
					else
						log.warn "API reported error", response.statusCode, err
						ts3query.sendtextmessage args.targetmode, invoker.id, "Sorry, an error occurred. Try again later."
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

# HTTP API
await services.find("api").start defer err
if err
	log.error "API could not start up, shutting down!"
	await module.exports.shutdown defer()
	process.exit 1