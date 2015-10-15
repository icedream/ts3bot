spawn = require("child_process").spawn
log = require("../logger")("BlackBox")
services = require("../services")
StreamSplitter = require("stream-splitter")
require_bin = require("../require_bin")

blackboxBinPath = require_bin "blackbox"

module.exports = class BlackBoxService extends services.Service
	dependencies: [
		"xvfb"
	]
	constructor: -> super "BlackBox",
		start: (cb) ->
			if @process
				cb? null, @process
				return

			calledCallback = false

			proc = null
			doStart = null
			doStart = () =>
				await services.find("xvfb").start defer(err)
				if err
					throw new Error "Dependency xvfb failed."

				proc = spawn blackboxBinPath, [ "-rc", "/dev/null" ],
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
						@log.warn "BlackBox terminated unexpectedly during startup."
						cb? new Error "BlackBox terminated unexpectedly."
					@log.warn "BlackBox terminated unexpectedly, restarting."
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
