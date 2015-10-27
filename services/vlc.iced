spawn = require("child_process").spawn
services = require("../services")
config = require("../config")
wc = require("webchimera.js")
StreamSplitter = require("stream-splitter")

module.exports = class VLCService extends services.Service
	dependencies: [
		"pulseaudio"
	]
	constructor: -> super "VLC",
		###
		# Starts an instance of VLC and keeps it ready for service.
		###
		start: (cb) ->
			if @_instance
				cb? null, @_instance
				return

			calledCallback = false

			instance = wc.createPlayer [
				"--aout", "pulse",
				"--no-video"
			]
			instance.audio.volume = 50

			@_instance = instance
			cb? null, @_instance

		###
		# Shuts down the VLC instance.
		###
		stop: (cb) ->
			if not @_instance
				cb?()
				return

			# TODO: Is there even a proper way to shut this down?
			@_instance = null

			cb?()

