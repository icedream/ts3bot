express = require "express"
url = require "url"
path = require "path"
spawn = require("child_process").spawn
net = require "net"
Socket = net.Socket
getLogger = require "../logger"
config = require "../config"
log = getLogger "API"
#PulseAudio = require "pulseaudio"
isValidUrl = (require "valid-url").isWebUri

services = require "../services"

module.exports = class APIService extends services.Service
	dependencies: [
		"pulseaudio"
		"vlc"
		"ts3client"
	]
	constructor: () -> super "API",
		start: (cb) ->
			if @httpServer
				cb? null
				return

			vlc = services.find("vlc").instance
			ts3query = services.find("ts3client").query

			# set up HTTP server
			log.debug "Starting up HTTP API..."
			app = express()
			app.get "/play", (req, res) =>
				if not req.query.uid
					log.debug "Didn't get a UID, sending forbidden"
					res.status(400).send("Forbidden")
					return
				if not req.query.input
					log.debug "Didn't get an input URI/alias, sending bad request"
					res.status(400).send("Bad request")
					return

				input = null
				# only allow playback from file if it's a preconfigured alias
				if isValidUrl req.query.input
					log.debug "Got input URL:", req.query.input
					input = req.query.input
				else
					input = config.get("aliases:#{req.query.input}")
					if not(isValidUrl input) and not(fs.existsSync input)
						log.debug "Got neither valid URL nor valid alias:", req.query.input
						res.status(403).send("Forbidden")
						return

				# TODO: permission system to check if uid is allowed to play this url or alias

				await vlc.status.empty defer(err)
				if err
					res.status(503).send("Something went wrong")
					log.warn "VLC API returned an error when trying to empty", err
					return

				await vlc.status.play input, defer(err)
				if err
					vlc.status.empty()
					res.status(503).send("Something went wrong")
					log.warn "VLC API returned an error when trying to play", err
					return

				res.send("OK")

			app.get "/stop", (req, res) =>
				if not req.query.uid
					log.debug "Didn't get a UID, sending forbidden"
					res.status(403).send("Forbidden - missing UID")
					return

				# TODO: permission system to check if uid is allowed to stop playback

				vlc.status.stop()
				vlc.status.empty()

				res.send("OK")

			app.get "/setvolume", (req, res) =>
				throw new "Not implemented yet" # FIXME below, still need to implement audio

			@httpServer = app.listen 16444

			cb? null

		stop: (cb) ->
			@httpServer.close()

			cb?()