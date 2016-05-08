spawn = require("child_process").spawn
log = require("../logger")("XWindowManager")
services = require("../services")
StreamSplitter = require("stream-splitter")
require_bin = require("../require_bin")

xwmBinPath = require_bin "x-window-manager", false

module.exports = class XWindowManagerService extends services.Service
	dependencies: [
	]
	constructor: -> super "XWindowManager",
		start: (cb) ->
			if not xwmBinPath?
				cb? new Error "A window manager not available."
				return

			if not process.env.XDG_RUNTIME_DIR? or process.env.XDG_RUNTIME_DIR.trim() == ""
				cb? new Error "XDG runtime directory needs to be set."
				return

			if not process.env.DISPLAY? or process.env.DISPLAY.trim() == ""
				cb? new Error "There is no display to run TeamSpeak3 on."
				return

			if @process
				cb? null, @process
				return

			calledCallback = false

			proc = null
			doStart = null
			doStart = () =>
				proc = spawn xwmBinPath, [],
					stdio: ['ignore', 'pipe', 'pipe']
					detached: true
					env:
						DISPLAY: process.env.DISPLAY
						XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR
						HOME: process.env.HOME

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
					@log.warn token

				proc.on "exit", () =>
					if @state == "stopping"
						return
					if not calledCallback
						calledCallback = true
						@log.warn "Window manager terminated unexpectedly during startup."
						cb? new Error "Window manager terminated unexpectedly."
					@log.warn "Window manager terminated unexpectedly, restarting."
					doStart()

				@process = proc

			doStart()

			setTimeout (() =>
				if not calledCallback
					calledCallback = true
					cb? null, @process), 1500 # TODO: Use some more stable condition

		stop: (cb) ->
			if not @process
				cb?()
				return

			@process.kill()
			await @process.once "exit", defer()

			cb?()
