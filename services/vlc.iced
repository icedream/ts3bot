spawn = require("child_process").spawn
services = require("../services")
config = require("../config")
VLCApi = require("vlc-api")
StreamSplitter = require("stream-splitter")
require_bin = require("../require_bin")

vlcBinPath = require_bin "vlc"

module.exports = class VLCService extends services.Service
	dependencies: [
		"pulseaudio"
	]
	constructor: -> super "VLC",
		start: (cb) ->
			if @_process
				cb? null, @_process
				return

			calledCallback = false

			proc = null
			doStart = null
			doStart = () =>
				await services.find("pulseaudio").start defer(err)
				if err
					throw new Error "Dependency pulseaudio failed."

				proc = spawn vlcBinPath, [
					"-I", "http",
					"--http-host", config.get("vlc-host"),
					"--http-port", config.get("vlc-port"),
					"--http-password", config.get("vlc-password")
					"--aout", "pulse",
					"--volume", "128", # 50% volume
					"--no-video"
				],
					stdio: ['ignore', 'pipe', 'pipe']
					detached: true

				# logging
				stdoutTokenizer = proc.stdout.pipe StreamSplitter "\n"
				stdoutTokenizer.encoding = "utf8";
				stdoutTokenizer.on "token", (token) =>
					token = token.trim() # get rid of \r
					@log.debug token

				stderrTokenizer = proc.stderr.pipe StreamSplitter "\n"
				stderrTokenizer.encoding = "utf8";
				stderrTokenizer.on "token", (token) =>
					token = token.trim() # get rid of \r
					@log.debug token

				proc.on "exit", () =>
					if @state == "stopping"
						return
					if not calledCallback
						calledCallback = true
						@log.warn "VLC terminated unexpectedly during startup."
						cb? new Error "VLC terminated unexpectedly."
					@log.warn "VLC terminated unexpectedly, restarting."
					doStart()

				@_process = proc

			doStart()

			setTimeout (() =>
				if not calledCallback
					calledCallback = true

					@instance = new VLCApi
						host: ":#{encodeURIComponent config.get("vlc-password")}@#{config.get("vlc-host")}",
						port: config.get("vlc-port")
					cb? null, @instance), 1500 # TODO: Use some more stable condition

		stop: (cb) ->
			if not @_process
				cb?()
				return

			@instance = null

			@_process.kill()
			await @_process.once "exit", defer()

			cb?()

