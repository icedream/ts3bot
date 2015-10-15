Sync = require "sync"

getLogger = require "./logger"
EventEmitter = require("events").EventEmitter
merge = require "merge"
services = require "./services"

module.exports = class Service extends EventEmitter
	constructor: (@name, funcs) ->
		@log = getLogger @name
		@_funcs = funcs
		@_funcs.log = @log # for bind lovers and coffeescript fat arrow (=>) lovers

		@on "started", => @emit "_ready"
		@on "stopped", => @emit "_ready"

		if not @dependencies
			@dependencies = []

	state: "stopped"

	start: () => @_start.apply @, [ false ].concat Array.prototype.slice.call(arguments)

	startSync: () => Sync () => @start.sync @

	_start: (quiet, args...) =>
		if typeof quiet != "boolean"
			throw new "quiet parameter must be a boolean"

		serviceArgs = args.slice 0
		cb = serviceArgs.pop()
		if typeof cb != "function"
			throw new Error "Callback needs to be given and needs to be a function"

		# wait until state is definite
		if @state != "started" and @state != "stopped"
			await @on "_ready", defer()

		if @state != "stopped"
			@log.warn "Requested startup of #{@name} but it needs to be stopped, current state is #{@state}."
			if @state == "started"
				@_funcs.start.apply @, serviceArgs.concat [ cb ] # start should return service object and null-error to callback
			else
				cb? new Error "Invalid state"
			return

		# make sure dependencies are running
		dependencyServices = []
		for serviceName in @dependencies
			service = services.find serviceName
			if not service
				@log.error "Could not find dependency #{serviceName}!"
				cb? new Error "Dependency #{serviceName} not found"
				return
			dependencyServices.push service
		dependencyServices.sort require("./service_depcomparer") # sort services by dependency
		for service in dependencyServices
			if service.state != "started"
				await service.start defer err
				if err
					@log.error "Dependency #{service.name} failed, can't start #{@name}"
					cb? new Error "Dependency #{service.name} failed"
					return

		if not quiet
			@log.info "Starting #{@name}"

		@state = "starting"
		@emit "starting"

		await @_funcs.start.apply @, serviceArgs.concat [ defer(err, service) ]
		if err
			cb? err
			@emit "startfail", err
			@state = "stopped"
			return

		if not quiet
			@log.info "Started #{@name}"

		@_lastArgs = args

		@state = "started"
		@emit "started", service

		cb? null, service

	stop: () => @_stop.apply @, [ false ].concat Array.prototype.slice.call(arguments)

	stopSync: () => Sync () => @stop.sync @

	_stop: (quiet, args...) =>
		if typeof quiet != "boolean"
			throw new "quiet parameter must be a boolean"

		serviceArgs = args.slice 0
		cb = serviceArgs.pop()
		if typeof cb != "function"
			throw new Error "Callback needs to be given and needs to be a function"

		# wait until state is definite
		if @state != "started" and @state != "stopped"
			await @on "_ready", defer()

		if @state != "started"
			@log.warn "Requested shutdown of #{@name} but it needs to be started, current state is #{@state}."
			cb? new Error "Invalid state"
			return

		if not quiet
			@log.info "Stopping #{@name}"

		@state = "stopping"
		@emit "stopping"

		await @_funcs.stop.apply @, serviceArgs.concat [ defer(err, service) ]
		if err
			cb? err
			@state = "started"
			@emit "stopfail", err
			return

		if not quiet
			@log.info "Stopped #{@name}"

		@state = "stopped"
		@emit "stopped"

		cb?()

	restart: (cb) =>
		# wait until state is definite
		if @state != "started" and @state != "stopped"
			await @on "_ready", defer()

		@log.info "Restarting #{@name}"
		@emit "restarting"

		if @state == "started"
			await @_stop true, defer(err)
			if err
				cb? err

		if @state == "stopped"
			await @_start true, @_lastArgs..., defer(err)
			if err
				cb? err

		@log.info "Restarted #{@name}"
		@emit "restarted"

		cb? err

	restartSync: () => Sync () => @restart.sync @