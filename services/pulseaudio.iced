spawn = require("child_process").spawn
log = require("../logger")("PulseAudio")
services = require("../services")
config = require("../config")
StreamSplitter = require("stream-splitter")
require_bin = require("../require_bin")

pulseaudioPath = require_bin config.get("PULSE_BINARY")
pacmdPath = require_bin "pacmd"

module.exports = class PulseAudioService extends services.Service
	dependencies: [
	]
	constructor: -> super "PulseAudio",
		start: (cb) ->
			if @process
				cb? null, @process
				return

			# logging
			forwardLog = (token) =>
				token = token.trim() # get rid of \r
				level = token.substring(0, 1).toUpperCase()
				msg = token.substring token.indexOf("]") + 2
				switch token.substring(0, 1).toUpperCase()
					when "D" then log.silly msg
					when "I" then log.silly msg
					when "W" then log.warn msg
					when "E" then log.error msg
					else log.silly msg

			# spawn options
			opts =
				stdio: ['ignore', 'pipe', 'pipe']
				detached: true
				env:
					DISPLAY: process.env.DISPLAY
					HOME: process.env.HOME
					XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR

			# check if there is already a daemon running
			proc = spawn pulseaudioPath, [ "--check" ], opts
			stderrTokenizer = proc.stderr.pipe StreamSplitter "\n"
			stderrTokenizer.encoding = "utf8";
			stderrTokenizer.on "token", forwardLog
			await proc.once "exit", defer(code, signal)
			@log.silly "PulseAudio daemon check returned that #{if code == 0 then "a daemon is already running" else "no daemon is running"}"
			if code == 0
				@log.warn "PulseAudio already running on this system"
				cb? null, null
				return

			proc = spawn pulseaudioPath, [
				"--start"
				"--fail=true" # quit on startup failure
				"--daemonize=false"
				"-v"
			], opts

			calledCallback = false

			# logging
			tokenHandler = (token) =>
				forwardLog token

				if not calledCallback and (token.indexOf("client.conf") >= 0 or token.indexOf("Daemon startup complete.") >= 0)
					calledCallback = true
					@process = proc
					setTimeout (() => cb? null, @process), 1500 # TODO: Use some more stable condition
			stdoutTokenizer = proc.stdout.pipe StreamSplitter "\n"
			stdoutTokenizer.encoding = "utf8"
			stdoutTokenizer.on "token", tokenHandler
			stderrTokenizer = proc.stderr.pipe StreamSplitter "\n"
			stderrTokenizer.encoding = "utf8"
			stderrTokenizer.on "token", tokenHandler

			proc.on "exit", () =>
				if not calledCallback
					calledCallback = true
					cb? new Error "PulseAudio daemon terminated unexpectedly."

		stop: (cb) ->
			if not @process
				cb?()
				return

			@process.kill()
			await @process.once "exit", defer()

			cb?()

	findIndexForProcessId: (pid, cb) => throw new Error "Not implemented yet"

	findIndexForProcessIdSync: (pid) => Sync () => @findIndexForProcessId @, pid

	setSinkInputMute: (index, value, cb) => throw new Error "Not implemented yet"

	setSinkInputMuteSync: (index, value) => Sync () => @setSinkInputMute @, index, value

	mute: (index) => @setSinkInputMute index, 1
	unmute: (index) => @setSinkInputMute index, 0
