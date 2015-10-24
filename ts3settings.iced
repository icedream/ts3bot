sqlite3 = require("sqlite3") #.verbose()
SQLite3Database = sqlite3.Database
path = require "path"
mkdirp = require "mkdirp"
SimpleIni = require "simple-ini"
fs = require "fs"
merge = require "merge"
getLogger = require "./logger"

# some properties sugar from http://bl.ocks.org/joyrexus/65cb3780a24ecd50f6df
Function::getter = (prop, get) ->
  Object.defineProperty @prototype, prop, {get, configurable: yes}
Function::setter = (prop, set) ->
  Object.defineProperty @prototype, prop, {set, configurable: yes}

module.exports = class SettingsFile
	db: null
	identities: null
	defaultIdentity: null

	constructor: (@configPath) ->
		@log = getLogger "TS3Settings"

		try
			mkdirp.sync @configPath
		catch err
			throw new Error "Could not create TS3 config directory."

	@getter "isInitialized", -> () => fs.existsSync(path.join(@configPath, "settings.db")) and fs.existsSync(path.join(@configPath, "ts3clientui_qt.secrets.conf"))
	@getter "isReady", -> () => @db != null

	open: (cb) =>
		# settings database
		@db = new SQLite3Database path.join(@configPath, "settings.db")
		await @db.serialize defer()
		await @query "CREATE TABLE IF NOT EXISTS TS3Tables (key varchar NOT NULL UNIQUE,timestamp integer unsigned NOT NULL)", defer()

		# secrets file
		@identities = []
		@defaultIdentity = null
		secretsPath = path.join(@configPath, "ts3clientui_qt.secrets.conf")
		if fs.existsSync(secretsPath)
			secrets = new SimpleIni (() => fs.readFileSync(secretsPath, "utf-8")),
				quotedValues: false
			for i in [1 .. secrets.Identities.size]
				@identities.push
					id: secrets.Identities["#{i}/id"]
					identity: secrets.Identities["#{i}/identity"]
					nickname: secrets.Identities["#{i}/nickname"]
			@defaultIdentity = secrets.Identities.SelectedIdentity
		cb?()

	close: (cb) =>
		if not @isReady
			@log.warn "Tried to close TS3 settings when already closed"
			return

		await @db.close defer()

		# Build secrets INI structure
		secrets = new SimpleIni null,
			quotedValues: false
		secrets.General = {}
		secrets.Bookmarks =
			size: 0
		secrets.Identities =
			size: @identities.length
		index = 1
		for identity in @identities
			for key, value of identity
				secrets.Identities["#{index}/#{key}"] = value
			index++
		if @defaultIdentity
			secrets.Identities.SelectedIdentity = @defaultIdentity

		# Generate INI content
		await secrets.save defer(iniText)
		fs.writeFileSync path.join(@configPath, "ts3clientui_qt.secrets.conf"), iniText

		@identities = null
		@defaultIdentity = null
		@db = null

		cb?()

	setMultiple: (sets, cb) =>
		for set in sets
			await @set set[0], set[1], set[2], defer(err)
			if err
				throw err
		cb?()

	set: (table, key, value, cb) =>
		if not @isReady
			throw new Error "You need to run open on this instance of TS3Settings first"
			return

		if not table
			throw new Error "Need table"

		await @query "create table if not exists #{table} (timestamp integer unsigned NOT NULL, key varchar NOT NULL UNIQUE, value varchar)", defer()

		if not key
			return

		if not (typeof value == "string" || value instanceof String)
			# serialize from object to ts3 dict text
			strval = ""
			for own k of value
				strval += k + "=" + value[k] + "\n"
			value = strval

		timestamp = Math.round (new Date).getTime() / 1000

		stmt = @db.prepare "insert or replace into TS3Tables (key, timestamp) values (?, ?)"
		stmt.run table, timestamp
		await stmt.finalize defer()

		stmt = @db.prepare "insert or replace into #{table} (timestamp, key, value) values (?, ?, ?)"
		stmt.run timestamp, key, value
		await stmt.finalize defer()

		cb?()

	query: (stmt, cb) =>
		if not @isReady
			throw new Error "You need to run open on this instance of TS3Settings first"
			return

		await @db.run stmt, defer()
		cb?()

	importIdentity: (identityFilePath, cb) =>
		if not @isReady
			throw new Error "You need to run open on this instance of TS3Settings first"
			return

		if not identityFilePath
			throw new Error "Need identity file path"

		@log.info "Importing identity from #{identityFilePath}..."

		# open identity file
		idFile = new SimpleIni (() => fs.readFileSync(identityFilePath, "utf-8")),
			quotedValues: true
		importedIdentity = {}
		for own k, v of idFile.Identity
			importedIdentity[k] = v

		for identity in @identities
			if identity.id == importedIdentity.id
				throw new Error "Identity with same ID already exists"

		@identities.push importedIdentity
		@log.info "Identity #{importedIdentity.id} imported successfully!"

		cb? @constructIdentityObject importedIdentity

	importIdentitySync: (identityFilePath) =>
		await @importIdentity identityFilePath, defer retval
		return retval

	getIdentities: (cb) =>
		if not @isReady
			throw new Error "You need to run open on this instance of TS3Settings first"
			return

		identities = []

		for identity in @identities
			identities.push @constructIdentityObject identity

		cb? identities

	getIdentitiesSync: () =>
		await @getIdentities defer retval
		return retval

	getIdentitiesSize: () =>
		if not @isReady
			throw new Error "You need to run open on this instance of TS3Settings first"
			return

		@identities.length

	getSelectedIdentity: () =>
		if not @isReady
			throw new Error "You need to run open on this instance of TS3Settings first"
			return

		if not @defaultIdentity
			return null

		for own index, identity of @identities
			if identity.id == @defaultIdentity
				return @constructIdentityObject identity

	clearIdentities: () =>
		if not @isReady
			throw new Error "You need to run open on this instance of TS3Settings first"
			return

		@log.debug "Clearing all identities"
		@identities.length = 0
		return

	constructIdentityObject: (id) =>
		settingsObj = @
		clonedId = merge(true, id)
		return merge clonedId, # true causes object to be cloned
			select: () ->
				settingsObj.defaultIdentity = @id
			update: () ->
				settingsObj.silly "Requested update of #{id.id}"
				for own index, identity of settingsObj.identities
					if identity.id == id.id
						settingsObj.silly "Updating identity #{id.id}"
						settingsObj.identities[index] = merge identity, id
						return
			remove: () ->
				for own index, identity of settingsObj.identities
					if identity.id == id.id
						delete settingsObj.identities[index]
						break
				# TODO: Select another identity as default