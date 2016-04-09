require "string.prototype.startswith"

net = require "net"
getLogger = require "./logger"
StringDecoder = require("string_decoder").StringDecoder
StreamSplitter = require "stream-splitter"
events = require "events"
EventEmitter = events.EventEmitter
merge = require "merge"

parserLog = getLogger "parser"

escape = (value) => value.toString()\
	.replace(/\\/g, "\\\\")\
	.replace(/\//g, "\\/")\
	.replace(/\|/g, "\\p")\
	.replace(/\n/g, "\\n")\
	.replace(/\r/g, "\\r")\
	.replace(/\t/g, "\\t")\
	.replace(/\ /g, "\\s")

unescape = (value) => value.toString()\
	.replace(/\\s/g, " ")\
	.replace(/\\t/g, "\t")\
	.replace(/\\r/g, "\r")\
	.replace(/\\n/g, "\n")\
	.replace(/\\p/g, "|")\
	.replace(/\\\//g, "/")\
	.replace(/\\\\/g, "\\")

buildCmd = (name, namedArgs, posArgs) =>
	# TODO: Add support for collected arguments (aka lists)
	if not name
		throw new Error "Need command name"
	if name.indexOf(" ") >= 0
		throw new Error "Invalid command name"
	if name.length > 0
		param = "#{name}"
	if namedArgs
		for k, v of namedArgs
			if v == null
				continue
			if param.length > 0
				param += " "
			param += "#{escape(k)}=#{escape(v)}"
	if posArgs
		for v in posArgs
			if v == null
				continue
			if param.length > 0
				param += " "
			param += "#{escape(v)}"
	param + "\n\r"

parseCmd = (str) =>
	params = str.split " "

	startIndex = 0
	if params[0].indexOf("=") < 0
		name = params[0]
		str = str.substring name.length + 1

	str = str.split "|" # TODO: Ignore escaped pipes

	collectedArgs = []

	for s in str
		params = s.split " "
		args = {}
		posArgs = []

		for i in [0 .. params.length - 1]
			value = params[i]
			equalsPos = value.indexOf "="
			if equalsPos < 0
				posArgs.push value
				continue
			key = unescape value.substring(0, equalsPos)
			value = value.substring equalsPos + 1
			value = unescape value
			args[key] = value

		args._ = posArgs

		collectedArgs.push args

	if collectedArgs.length == 1
		collectedArgs = collectedArgs[0]

	{
		name: name
		args: collectedArgs
	}

checkError = (err) =>
	err.id = parseInt err.id
	if err.id == 0
		return null
	err

module.exports = class TS3ClientQuery extends EventEmitter
	constructor: (host, port) ->
		@_log = getLogger "TS3ClientQuery"
		@_id = null
		@_host = host
		@_port = port

	connect: (cb) =>
		@_tcpClient = new net.Socket

		@_tcpClient.on "close", () =>
			@_stopKeepalive()
			@emit "close"
		@_tcpClient.on "error", (err) =>
			@_log.warn "Connection error", err
			@_stopKeepalive()
			@_tcpClient = null
			@emit "error", err

		@emit "connecting"
		@_tcpClient.connect @_port, @_host, () =>
			@emit "open"
			await @once "message.selected", defer(selectedArgs)
			cb?()

		splitterStream = StreamSplitter("\n\r")
		splitterStream.encoding = "utf8"

		@_tcpTokenizer = @_tcpClient.pipe splitterStream

		@_tcpTokenizer.on "token", (token) =>
			token = token.trim()

			if token.startsWith "TS3 Client" or token.startsWith "Welcome"
				return # this is just helper text for normal users

			response = parseCmd token

			@_log.silly "Recv:", token

			if response.name
				@emit "message.#{response.name}", response.args
			else
				@emit "vars", response.args

		# send keepalives to avoid connection timeout
		@_resetKeepalive()

	_sendKeepalive: (cb) =>
		@_log.silly "Send: <keep-alive>"

		@_tcpClient.write "\n\r", "utf8", () => cb?()

	_stopKeepalive: () =>
		if @_keepaliveInt?
			clearInterval @_keepaliveInt
			@_keepaliveInt = null

	_resetKeepalive: () =>
		@_stopKeepalive()
		@_keepaliveInt = setInterval @_sendKeepalive, 60000

	close: (cb) =>
		@_stopKeepalive()
		if not @_tcpClient
			cb?()
			return
		@_tcpClient.destroy()
		cb?()

	send: (cmd, namedArgs, positionalArgs, cb) =>
		if not cmd
			throw new Error "Need command name"

		if Array.isArray namedArgs
			cb = positionalArgs
			positionalArgs = namedArgs
			namedArgs = {}

		if typeof positionalArgs == "function"
			cb = positionalArgs
			positionalArgs = []

		text = buildCmd(cmd, namedArgs, positionalArgs)

		@_log.silly "Send:", text.trim()

		@_tcpClient.write text, "utf8", () => cb?()
		@_resetKeepalive()

	banadd: (cb) =>
		throw new Error "Not implemented yet"

	banclient: (cb) =>
		throw new Error "Not implemented yet"

	bandel: (cb) =>
		throw new Error "Not implemented yet"

	bandelall: (cb) =>
		throw new Error "Not implemented yet"

	banlist: (cb) =>
		throw new Error "Not implemented yet"

	channeladdperm: (cb) =>
		throw new Error "Not implemented yet"

	channelclientaddperm: (cb) =>
		throw new Error "Not implemented yet"

	channelclientdelperm: (cb) =>
		throw new Error "Not implemented yet"

	channelclientlist: (cb) =>
		throw new Error "Not implemented yet"

	channelclientpermlist: (cb) =>
		throw new Error "Not implemented yet"

	###
	Get channel connection information for specified channelid from the currently
	selected server connection handler. If no channelid is provided, information
	for the current channel will be received.
	###
	channelconnectinfo: (cid, cb) =>
		if not cb and typeof cid == "function"
			cb = cid
			cid = null
		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "channelconnectinfo",
			cid: cid

	###
	Creates a new channel using the given properties and displays its ID.

	N.B. The channel_password property needs a hashed password as a value.
	The hash is a sha1 hash of the password, encoded in base64. You can
	use the "hashpassword" command to get the correct value.
	###
	channelcreate: (channel_name, channel_properties, cb) =>
		if not cb and typeof channel_properties == "function"
			cb = channel_properties
			channel_properties = {}
		if not channel_properties
			channel_properties = {}
		channel_properties["channel_name"] = channel_name
		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "channelcreate", channel_properties

	channeldelete: (cb) =>
		throw new Error "Not implemented yet"

	channeldelperm: (cb) =>
		throw new Error "Not implemented yet"

	###
	Changes a channels configuration using given properties.
	###
	channeledit: (cid, channel_properties, cb) =>
		@once "message.error", (args) => cb? checkError(args)
		@send "channeledit", merge true, channel_properties,
			cid: cid

	channelgroupadd: (cb) =>
		throw new Error "Not implemented yet"

	channelgroupaddperm: (cb) =>
		throw new Error "Not implemented yet"

	channelgroupclientlist: (cb) =>
		throw new Error "Not implemented yet"

	channelgroupdel: (cb) =>
		throw new Error "Not implemented yet"

	channelgroupdelperm: (cb) =>
		throw new Error "Not implemented yet"

	channelgrouplist: (cb) =>
		throw new Error "Not implemented yet"

	channelgrouppermlist: (cb) =>
		throw new Error "Not implemented yet"

	channellist: (cb) =>
		throw new Error "Not implemented yet"

	channelmove: (cb) =>
		throw new Error "Not implemented yet"

	channelpermlist: (cb) =>
		throw new Error "Not implemented yet"

	channelvariable: (cb) =>
		throw new Error "Not implemented yet"

	clientaddperm: (cb) =>
		throw new Error "Not implemented yet"

	clientdbdelete: (cb) =>
		throw new Error "Not implemented yet"

	clientdbedit: (cb) =>
		throw new Error "Not implemented yet"

	clientdblist: (cb) =>
		throw new Error "Not implemented yet"

	clientdelperm: (cb) =>
		throw new Error "Not implemented yet"

	###
	Displays the database ID matching the unique identifier specified by cluid.
	###
	clientgetdbidfromuid: (cluid, cb) =>
		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "clientgetdbidfromuid",
			cluid: cluid

	###
	Displays all client IDs matching the unique identifier specified by cluid.
	###
	clientgetids: (cb) =>
		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "clientgetids",
			cluid: cluid

	###
	Displays the unique identifier and nickname matching the database ID specified 
	by cldbid.
	###
	clientgetnamefromdbid: (cldbid, cb) =>
		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "clientgetnamefromdbid",
			cldbid: cldbid

	###
	Displays the database ID and nickname matching the unique identifier specified 
	by cluid.
	###
	clientgetnamefromuid: (cluid, cb) =>
		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "clientgetnamefromuid",
			cluid: cluid

	###
	Displays the unique identifier and nickname associated with the client
	specified by the clid parameter.
	###
	clientgetuidfromclid: (clid, cb) =>
		retval = { }
		@once "notifyclientuidfromclid", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "clientgetuidfromclid",
			clid: clid

	###
	Kicks one or more clients specified with clid from their currently joined 
	channel or from the server, depending on reasonid. The reasonmsg parameter 
	specifies a text message sent to the kicked clients. This parameter is optional 
	and may only have a maximum of 40 characters.

	Available reasonid values are:
	4: Kick the client from his current channel into the default channel
	5: Kick the client from the server
	###
	clientkick: (reasonid, reasonmsg, clid, cb) =>
		if not cb and not clid
			cb = clid
			clid = reasonmsg
			reasonmsg = null
		if typeof clid == "function"
			cb = clid
			clid = null
		@once "message.error", (args) => cb? checkError(args), retval
		@send "clientkick",
			reasonid: reasonid
			reasonmsg: reasonmsg
			clid: clid

	###
	Displays a list of clients that are known. Included information is the
	clientID, nickname, client database id, channelID and client type.
	Please take note that the output will only contain clients which are in
	channels you are currently subscribed to. Using the optional modifier
	parameters you can enable additional information per client.

	Here is a list of the additional display paramters you will receive for
	each of the possible modifier parameters.

	-uid:
	client_unique_identifier

	-away:
	client_away
	client_away_message

	-voice:
	client_flag_talking
	client_input_muted
	client_output_muted
	client_input_hardware
	client_output_hardware
	client_talk_power
	client_is_talker
	client_is_priority_speaker
	client_is_recording
	client_is_channel_commander
	client_is_muted

	-groups:
	client_servergroups
	client_channel_group_id

	-icon:
	client_icon_id

	-country:
	client_country
	###
	clientlist: (modifiers, cb) =>
		if not cb
			cb = modifiers
			modifiers = null

		cleanedModifiers = []
		for v, index in modifiers
			if not v.startsWith "-"
				v = "-#{v}"
			cleanedModifiers.push v

		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "clientlist", cleanedModifiers

	clientmove: (cb) =>
		throw new Error "Not implemented yet"

	clientmute: (cb) =>
		throw new Error "Not implemented yet"

	###
	This command allows you to listen to events that the client encounters. Events
	are things like people starting or stopping to talk, people joining or leaving,
	new channels being created and many more.
	It registers for client notifications for the specified
	serverConnectionHandlerID. If the serverConnectionHandlerID is set to zero it
	applies to all server connection handlers. Possible event values are listed
	below, additionally the special string "any" can be used to subscribe to all
	events.

	Possible values for event:
	  notifytalkstatuschange
	  notifymessage
	  notifymessagelist
	  notifycomplainlist
	  notifybanlist
	  notifyclientmoved
	  notifyclientleftview
	  notifycliententerview
	  notifyclientpoke
	  notifyclientchatclosed
	  notifyclientchatcomposing
	  notifyclientupdated
	  notifyclientids
	  notifyclientdbidfromuid
	  notifyclientnamefromuid
	  notifyclientnamefromdbid
	  notifyclientuidfromclid
	  notifyconnectioninfo
	  notifychannelcreated
	  notifychanneledited
	  notifychanneldeleted
	  notifychannelmoved
	  notifyserveredited
	  notifyserverupdated
	  channellist
	  channellistfinished
	  notifytextmessage
	  notifycurrentserverconnectionchanged
	  notifyconnectstatuschange
	###
	clientnotifyregister: (schandlerid, event, cb) =>
		@once "message.error", (args) => cb? checkError(args)
		@send "clientnotifyregister",
			schandlerid: schandlerid
			event: event

	###
	Unregisters from all previously registered client notifications.
	###
	clientnotifyunregister: (cb) =>
		@once "message.error", (args) => cb? checkError(args)
		@send "clientnotifyunregister"

	###
	Displays a list of permissions defined for a client.
	###
	clientpermlist: (cldbid, cb) =>
		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "clientpermlist",
			cldbid: cldbid

	###
	Sends a poke message to the client specified with clid.
	###
	clientpoke: (clid, msg, cb) =>
		if typeof msg == "function"
			cb = msg
			msg = null
		@once "message.error", (args) => cb? checkError(args)
		@send "clientpoke",
			msg: msg
			clid: clid

	clientunmute: (cb) =>
		throw new Error "Not implemented yet"

	###
	Sets one or more values concerning your own client, and makes them available
	to other clients through the server where applicable. Available idents are:

	client_nickname:             set a new nickname
	client_away:                 0 or 1, set us away or back available
	client_away_message:         what away message to display when away
	client_input_muted:          0 or 1, mutes or unmutes microphone
	client_output_muted:         0 or 1, mutes or unmutes speakers/headphones
	client_input_deactivated:    0 or 1, same as input_muted, but invisible to
	                             other clients
	client_is_channel_commander: 0 or 1, sets or removes channel commander
	client_nickname_phonetic:    set your phonetic nickname
	client_flag_avatar:          set your avatar
	client_meta_data:            any string that is passed to all clients that
	                             have vision of you.
	client_default_token:        privilege key to be used for the next server
	                             connect
	###
	clientupdate: (idents, cb) =>
		@once "message.error", (args) => cb? checkError(args)
		@send "clientupdate", idents

	###
	Retrieves client variables from the client (no network usage). For each client
	you can specify one or more properties that should be queried, and this whole
	block of clientID and properties can be repeated to get information about
	multiple clients with one call of clientvariable.

	Available properties are:
	client_unique_identifier
	client_nickname
	client_input_muted
	client_output_muted
	client_outputonly_muted
	client_input_hardware
	client_output_hardware
	client_meta_data
	client_is_recording
	client_database_id
	client_channel_group_id
	client_servergroups
	client_away
	client_away_message
	client_type
	client_flag_avatar
	client_talk_power
	client_talk_request
	client_talk_request_msg
	client_description
	client_is_talker
	client_is_priority_speaker
	client_unread_messages
	client_nickname_phonetic
	client_needed_serverquery_view_power
	client_icon_id
	client_is_channel_commander
	client_country
	client_channel_group_inherited_channel_id
	client_flag_talking
	client_is_muted
	client_volume_modificator

	These properties are always available for yourself, but need to be requested
	for other clients. Currently you cannot request these variables via
	clientquery:
	client_version
	client_platform
	client_login_name
	client_created
	client_lastconnected
	client_totalconnections
	client_month_bytes_uploaded
	client_month_bytes_downloaded
	client_total_bytes_uploaded
	client_total_bytes_downloaded

	These properties are available only for yourself:
	client_input_deactivated
	###
	clientvariable: (clid, variables, cb) =>
		if not clid
			throw new Error "Need client ID"
		if not Array.isArray variables
			throw new Error "variables needs to be an array of requested client variables."
		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "clientvariable", { clid: clid }, variables

	complainadd: (cb) =>
		throw new Error "Not implemented yet"

	complaindel: (cb) =>
		throw new Error "Not implemented yet"

	complaindelall: (cb) =>
		throw new Error "Not implemented yet"

	complainlist: (cb) =>
		throw new Error "Not implemented yet"

	###
	Get server connection handler ID of current server tab.
	###
	currentschandlerid: (cb) =>
		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "currentschandlerid"

	disconnect: (cb) => close(cb)

	exam: (cb) =>
		throw new Error "Not implemented yet"

	ftcreatedir: (cb) =>
		throw new Error "Not implemented yet"

	ftdeletefile: (cb) =>
		throw new Error "Not implemented yet"

	ftgetfileinfo: (cb) =>
		throw new Error "Not implemented yet"

	ftgetfilelist: (cb) =>
		throw new Error "Not implemented yet"

	ftinitdownload: (cb) =>
		throw new Error "Not implemented yet"

	ftinitupload: (cb) =>
		throw new Error "Not implemented yet"

	ftlist: (cb) =>
		throw new Error "Not implemented yet"

	ftrenamefile: (cb) =>
		throw new Error "Not implemented yet"

	ftstop: (cb) =>
		throw new Error "Not implemented yet"

	hashpassword: (cb) =>
		throw new Error "Not implemented yet"

	help: (cb) =>
		throw new Error "Not implemented yet"

	messageadd: (cb) =>
		throw new Error "Not implemented yet"

	messagedel: (cb) =>
		throw new Error "Not implemented yet"

	messageget: (cb) =>
		throw new Error "Not implemented yet"

	messagelist: (cb) =>
		throw new Error "Not implemented yet"

	messageupdateflag: (cb) =>
		throw new Error "Not implemented yet"

	permoverview: (cb) =>
		throw new Error "Not implemented yet"

	quit: (cb) => close(cb)

	###
	Sends a text message a specified target. The type of the target is determined 
	by targetmode.
	Available targetmodes are:
	1: Send private text message to a client. You must specify the target parameter
	2: Send message to the channel you are currently in. Target is ignored.
	3: Send message to the entire server. Target is ignored.
	###
	sendtextmessage: (targetmode, target, msg, cb) =>
		if targetmode != 1 and (not msg or typeof msg == "function")
			cb = msg
			msg = target
			target = null
		@once "message.error", (args) => cb? checkError(args)
		@send "sendtextmessage",
			targetmode: targetmode
			target: target
			msg: msg

	serverconnectinfo: (cb) =>
		throw new Error "Not implemented yet"

	serverconnectionhandlerlist: (cb) =>
		throw new Error "Not implemented yet"

	servergroupadd: (cb) =>
		throw new Error "Not implemented yet"

	servergroupaddclient: (cb) =>
		throw new Error "Not implemented yet"

	servergroupaddperm: (cb) =>
		throw new Error "Not implemented yet"

	servergroupclientlist: (cb) =>
		throw new Error "Not implemented yet"

	servergroupdel: (cb) =>
		throw new Error "Not implemented yet"

	servergroupdelclient: (cb) =>
		throw new Error "Not implemented yet"

	servergroupdelperm: (cb) =>
		throw new Error "Not implemented yet"

	servergrouplist: (cb) =>
		throw new Error "Not implemented yet"

	servergrouppermlist: (cb) =>
		throw new Error "Not implemented yet"

	servergroupsbyclientid: (cb) =>
		throw new Error "Not implemented yet"

	servervariable: (cb) =>
		throw new Error "Not implemented yet"

	setclientchannelgroup: (cb) =>
		throw new Error "Not implemented yet"

	tokenadd: (cb) =>
		throw new Error "Not implemented yet"

	tokendelete: (cb) =>
		throw new Error "Not implemented yet"

	tokenlist: (cb) =>
		throw new Error "Not implemented yet"

	###
	Use a token key gain access to a server or channel group. Please note that the
	server will automatically delete the token after it has been used.
	###
	tokenuse: (token, cb) =>
		@once "message.error", (args) => cb? checkError(args)
		@send "tokenuse",
			token: token

	###
	Selects the server connection handler scHandlerID or, if no parameter is given,
	the currently active server connection handler is selected.
	###
	use: (schandlerid, cb) =>
		retval = { }
		@once "message.selected", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "use",
			schandlerid: schandlerid

	verifychannelpassword: (cb) =>
		throw new Error "Not implemented yet"

	###
	Verifies the server password and will return an error if the password is
	incorrect.
	###
	verifyserverpassword: (password, cb) =>
		@once "message.error", (args) => cb? checkError(args)
		@send "verifyserverpassword",
			password: password

	###
	Retrieves information about ourself:
	- ClientID (if connected)
	- ChannelID of the channel we are in (if connected)

	If not connected, an error is returned.
	###
	whoami: (cb) =>
		retval = { }
		@once "vars", (args) => merge retval, args
		@once "message.error", (args) => cb? checkError(args), retval
		@send "whoami"
