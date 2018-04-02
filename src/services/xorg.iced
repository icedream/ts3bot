spawn = require("child_process").spawn
path = require("path")
log = require("../logger")("Xorg")
services = require("../services")
config = require("../config")
StreamSplitter = require("stream-splitter")
require_bin = require("../require_bin")

xorgPath = require_bin "Xorg"
xorgLogMatcher = /^\((--|\*\*|==|\+\+|!!|II|WW|EE|NI|\?\?)\) (.+)$/

module.exports = class XorgService extends services.Service
	dependencies: [
	]
	constructor: -> super "Xorg",
		start: (cb) ->
			if @process
				cb? null, @process
				return

			# logging
			forwardLog = (token) =>
				token = token.trim() # get rid of \r
				logMatch = xorgLogMatcher.exec token
				if logMatch
					switch logMatch[1].toUpperCase()
						# when "--": # probed
						# when "**": # from config file
						# when "==": # default setting
						# when "++": # from command line
						when "!!" then log.silly logMatch[2] # notice
						when "II" then log.info logMatch[2] # info
						when "WW" then log.warn logMatch[2] # warn
						when "NI" then log.warn logMatch[2] # not implemented
						when "EE" then log.error logMatch[2] # error
						else log.silly logMatch[2]
				else
					log.debug token

			# spawn options
			opts =
				stdio: ['ignore', 'pipe', 'pipe']
				detached: true
				env:
					DISPLAY: process.env.DISPLAY
					HOME: process.env.HOME
					XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR

			proc = spawn xorgPath, [
				"-noreset"
				"+extension", "GLX"
				"+extension", "RANDR"
				"+extension", "RENDER"
				"-logfile", "/dev/null"
				"-config", path.resolve(__dirname, "xorg.conf"),
				":99"
			], opts

			calledCallback = false

			# logging
			tokenHandler = (token) =>
				forwardLog token

				if not calledCallback and (token.indexOf("Using system config directory") >= 0)
					calledCallback = true
					@process = proc
					process.env.DISPLAY = ":99"
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
					cb? new Error "X server terminated unexpectedly."

		stop: (cb) ->
			if not @process
				cb?()
				return

			@process.kill()
			await @process.once "exit", defer()

			cb?()
