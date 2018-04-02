log = require("../logger")("TS3Client")
config = require("../config")
services = require("../services")
x11tools = require("../x11")
TS3Settings = require("../ts3settings")
TS3ClientQuery = require("../ts3query")
path = require "path"
merge = require "merge"
fs = require "fs"
url = require "url"
spawn = require("child_process").spawn
StreamSplitter = require("stream-splitter")
require_bin = require("../require_bin")

ts3client_binpath = require_bin path.join(config.get("ts3-install-path"), "ts3client_linux_" + (if process.arch == "x64" then "amd64" else process.arch))

randomApiKeyChars = [
	(x for x in ['0'..'9'])...
	(x for x in ['A'..'Z'])...
]

randomApiKey = () =>
	segments = []
	createSegment = () =>
		segment = ""
		segment += Math.random().toString(36).substr(0, 4).toUpperCase()
		return segment
	segments = (createSegment() for x in [0..4])
	return segments.join "-"

module.exports = class TS3ClientService extends services.Service
	dependencies: [
		"pulseaudio"
	]
	constructor: -> super "TS3Client",
		start: (args, cb) =>
			if not process.env.XDG_RUNTIME_DIR? or process.env.XDG_RUNTIME_DIR.trim() == ""
				cb? new Error "XDG runtime directory needs to be set."
				return

			if not process.env.DISPLAY? or process.env.DISPLAY.trim() == ""
				cb? new Error "There is no display to run TeamSpeak3 on."
				return

			if typeof args == "function"
				cb = args
				args = null

			if @process
				cb? null, @process
				return

			uri = null
			if not args
				args = []
			for v in args
				if v.indexOf("ts3server:") != 0
					continue
				uri = v
				break

			await fs.access ts3client_binpath, fs.R_OK | fs.X_OK, defer err
			if err
				log.error "Can't access TeamSpeak3 client binary at #{ts3client_binpath}, does the binary exist and have you given correct access?"
				cb? new Error "Access to TeamSpeak3 binary failed."
				return

			await @_preconfigure uri, defer()

			# spawn process
			proc = null
			doStart = null
			forwardLog = (token) =>
				token = token.trim() # get rid of \r
				if token.indexOf("|") > 0
					token = token.split("|")
					level = token[1].toUpperCase().trim()
					source = token[2].trim()
					sourceStr = if source then "#{source}: " else ""
					message = token[4].trim()
					switch level
						when "ERROR" then log.error "%s%s", sourceStr, message
						when "WARN" then log.warn "%s%s", sourceStr, message
						when "INFO" then log.debug "%s%s", sourceStr, message
						else log.silly "%s%s", sourceStr, message
				else
					log.debug token
			scheduleRestart = null # see below
			onExit = => # autorestart
				@_running = false
				@process = null
				if @_requestedExit
					return
				log.warn "TeamSpeak3 unexpectedly terminated!"
				scheduleRestart()
			reconnectFunc = () =>
				@query.connect()
			doStart = () =>
				env =
					HOME: process.env.HOME
					DISPLAY: process.env.DISPLAY
					XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR
					KDEDIRS: ''
					KDEDIR: ''
					QTDIR: config.get("ts3-install-path")
					QT_PLUGIN_PATH: config.get("ts3-install-path")
					LD_LIBRARY_PATH: config.get("ts3-install-path")
				if process.env.LD_LIBRARY_PATH
					env.LD_LIBRARY_PATH += ":#{process.env.LD_LIBRARY_PATH}"
				
				@log.silly "Environment variables:", env
				@log.silly "Arguments:", JSON.stringify args

				@_requestedExit = false
				proc = spawn ts3client_binpath, args,
					detached: true
					stdio: ['ignore', 'pipe', 'pipe']
					cwd: config.get("ts3-install-path")
					env: env
				@_running = true

				# logging
				stdoutTokenizer = proc.stdout.pipe StreamSplitter "\n"
				stdoutTokenizer.encoding = "utf8";
				stdoutTokenizer.on "token", forwardLog

				stderrTokenizer = proc.stderr.pipe StreamSplitter "\n"
				stderrTokenizer.encoding = "utf8";
				stderrTokenizer.on "token", forwardLog

				# connect to client query plugin when it's loaded
				stdoutTokenizer.on "token", (token) =>
					if token.indexOf("Loading plugin: libclientquery_plugin") >= 0
						# client query plugin is now loading
						@_queryReconnectTimer = setTimeout reconnectFunc, 1000
				stderrTokenizer.on "token", (token) =>
					if token.indexOf("Query: bind failed") >= 0
						# without query this ts3 instance is worthless
						await @_ts3GracefulShutdown defer()
						scheduleRestart()

				# autorestart
				proc.on "exit", onExit

				@process = proc
			scheduleRestart = () =>
				log.warn "Restarting in 5 seconds..."
				@_startTimer = setTimeout doStart.bind(@), 5000
				if @_queryReconnectTimer
					clearTimeout @_queryReconnectTimer
			doStart()

			# ts3 query
			@query = new TS3ClientQuery "127.0.0.1", 25639, @apiKey
			@_queryReconnectTimer = null
			@query.on "error", (err) =>
				log.warn "Error in TS3 query connection", err
			@query.on "close", =>
				if not @_requestedExit
					log.warn "Connection to TS3 client query interface lost, reconnecting..."
					@_queryReconnectTimer = setTimeout reconnectFunc, 1000
				else
					log.debug "Connection to TS3 client query interface lost."
			@query.on "open", =>
				log.debug "Connected to TS3 client query interface."
				await @query.auth @apiKey
			@query.on "connecting", => log.debug "Connecting to TS3 client query interface..."

			cb? null, @process

		stop: (cb) -> @_ts3GracefulShutdown cb

	_ts3GracefulShutdown: (cb) ->
		@_requestedExit = true

		if @_startTimer
			clearTimeout @_startTimer

		if @_queryReconnectTimer
			clearTimeout @_queryReconnectTimer

		if @_running
			log.silly "Using xdotool to gracefully shut down TS3"
			await x11tools.getWindowIdByProcessId @process.pid, defer(err, wid)
			if not wid
				log.debug "Can not find a window for #{@name}."
				log.warn "Can not properly shut down #{@name}, it will time out on the server instead."
				@process.kill()
			else
				log.silly "Sending keys to TS3"
				await x11tools.sendKeys wid, "ctrl+q", defer(err)
				if err
					log.warn "Can not properly shut down #{@name}, it will time out on the server instead."
					log.silly "Using SIGTERM for shutdown of #{@name}"
					@process.kill()

			# wait for 10 seconds then SIGKILL if still up
			log.silly "Now waiting 10 seconds for shutdown..."
			killTimer = setTimeout (() =>
				log.silly "10 seconds gone, using SIGKILL now since we're impatient."
				@process.kill("SIGKILL")), 10000
			await @process.once "exit", defer()
			clearTimeout killTimer

			@_running = false
			@process = null
		else
			log.warn "TeamSpeak3 seems to have died prematurely."

		cb?()

	_preconfigure: (uriString, cb) =>
		uri = url.parse(uriString, true, true) if uriString?

		ts3settings = new TS3Settings config.get("ts3-config-path")
		await ts3settings.open defer()

		# Delete bookmarks to prevent auto-connect bookmarks from weirding out the client
		await ts3settings.query "delete * from Bookmarks", defer()

		# Delete all profiles so we can enforce our own
		await ts3settings.query "delete * from Profiles", defer()

		# Let's make sure we have an identity!
		force = ts3settings.getIdentitiesSize() <= 0 or config.get("identity-path")
		if force
			if not config.get("identity-path")
				throw new Error "Need a file to import the bot's identity from."
			ts3settings.clearIdentities()
			await ts3settings.importIdentity config.get("identity-path"), defer(identity)
			identity.select()

		if config.get("nickname")
			# Enforce nickname from configuration
			identity = ts3settings.getSelectedIdentity()
			identity.nickname = config.get "nickname"
			identity.update()

		# Some settings to help the TS3Bot to do what it's supposed to do
		now = new Date()
		await ts3settings.setMultiple [
			[ "Application", "HotkeyMode", "2" ]
			[ "Chat", "MaxLines", "1" ]
			[ "Chat", "LogChannelChats", "0" ]
			[ "Chat", "LogClientChats", "0" ]
			[ "Chat", "LogServerChats", "0" ]
			[ "Chat", "ReloadChannelChats", "0" ]
			[ "Chat", "ReloadClientChats", "0" ]
			[ "Chat", "IndicateChannelChats", "0" ]
			[ "Chat", "IndicatePrivateChats", "0" ]
			[ "Chat", "IndicateServerChats", "0" ]
			[ "ClientLogView", "LogLevel", "000001" ]
			[ "FileTransfer", "SimultaneousDownloads", "2" ]
			[ "FileTransfer", "SimultaneousUploads", "2" ]
			[ "FileTransfer", "UploadBandwidth", "0" ]
			[ "FileTransfer", "DownloadBandwidth", "0" ]
			[ "General", "LicenseVersion", "2" ] # ugh...
			[ "General", "LastShownLicense", "2" ] # ugh...
			[ "General", "LastShownLicenseLang", "en" ]
			[ "General", "SyncOverviewShown", "1" ]
			[ "Global", "MainWindowMaximized", "1" ]
			[ "Global", "MainWindowMaximizedScreen", "1" ]
			[ "Messages", "Disconnect", config.get "quit-message" ]
			[ "Misc", "WarnWhenMutedInfoShown", "1" ]
			[ "Misc", "LastShownNewsBrowserVersion", "4" ]
			[ "News", "NewsClosed", "1" ]
			[ "News", "Language", "en" ]
			[ "News", "LastModified", now.toISOString() ]
			[ "News", "NextCheck", new Date(now.getTime() + 1000 * 60 * 60 * 24 * 365).toISOString() ]
			[ "Notifications", "SoundPack", "nosounds" ]
			[ "Plugins", "teamspeak_control_plugin", "false" ]
			[ "Plugins", "clientquery_plugin", "true" ]
			[ "Plugins", "lua_plugin", "false" ]
			[ "Plugins", "test_plugin", "false" ]
			[ "Plugins", "ts3g15", "false" ]
			# Intentionally leaving out DefaultPlaybackProfile so TS3Client will trick itself into using the blank profile
			[ "Profiles", "Playback/", {} ]
			[ "Profiles", "DefaultCaptureProfile", "Default" ]
			[ "Profiles", "Capture/Default", {
				Device: ''
				DeviceDisplayName: "Default"
				Mode: "PulseAudio"
				} ]
			[ "Profiles", "Capture/Default/PreProcessing", {
				continous_transmission: "false"
				vad: "true"
				vad_over_ptt: "false"
				delay_ptt_msecs: "250"
				voiceactivation_level: "-49"
				echo_reduction: false
				echo_cancellation: false
				denoise: false
				delay_ptt: false
				agc: if config.get("ts3-agc") then "true" else "false"
				echo_reduction_db: 10
				} ]
			[ "Statistics", "ParticipateStatistics", "0" ]
			[ "Statistics", "ConfirmedParticipation", "1" ]
			[ "Synchronization", "KeepAccountSession", "0" ]
			[ "Synchronization", "UsingSynchronization", "0" ]
			[ "Synchronization", "SynchronizationUserMode", "0" ]
			[ "ProtobufItems", "1", new Buffer("122431313131313131312d616161612d616161612d616161612d61616161616161616161616120002a2466666666666666662d666666662d666666662d666666662d66666666666666666666666630053a00420048dcf489d605aa010408011801", "hex") ]
		], defer()

		if uri?
			bookmarkId = "{5125344e-45ec-4510-9bbf-8b940628c5d0}"
			bookmarkData =
				Name: uriString
				Address: uri.hostname or "localhost"
				Port: uri.port or 9987
				CaptureProfile: "Default"
				PlaybackProfile: ""
				Identity: "Standard"
				Nick: uri.nickname or config.get("nickname") or "TS3Bot"
				Autoconnect: false
				ShowServerQueryClients: false
				Uuid: bookmarkId
			bookmarkData.ServerUID = uri.query?.server_uid if uri.query?.server_uid?
			await ts3settings.set "Bookmarks", bookmarkId, bookmarkData, defer()

		ts3settings.clientquery.General = {}
		ts3settings.clientquery.General.open_remote = "false"
		ts3settings.clientquery.General.logging_enabled = "true"
		@apiKey = randomApiKey()
		ts3settings.clientquery.General.api_key = @apiKey

		await ts3settings.close defer()

		cb?()
