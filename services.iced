# At this point I feel like I'm writing my own init system. Phew...

merge = require "merge"
getLogger = require("./logger")
EventEmitter = require("events").EventEmitter
log = getLogger("ServiceMgr")
Sync = require "sync"

getLegacyServiceName = (serviceName) -> serviceName.toLowerCase().replace(/[^A-z0-9]/g, "_")

module.exports =
	services: []

	find: (serviceName) ->
		serviceNameUpper = serviceName.toUpperCase()
		for service in services
			if service.name.toUpperCase() == serviceNameUpper
				return service
		null

	register: (service) ->
		if @[service.name]
			throw new Error "There is already a service registered under that name"
		@services.push service
		log.debug "Registered service #{service.name}"

	unregister: (serviceName) ->
		for service, index in @services
			if service.name == serviceName
				@services.splice index, 1
				log.debug "Unregistered service #{service.name}"
		throw new Error "There is no service registered under that name"

	shutdown: (cb) ->
		shutdownOrder = @services.splice 0
		shutdownOrder.reverse()

		while true
			for own k, v of shutdownOrder
				if v.state == "stopped"
					continue
				await v.stop defer()
			breakOut = true
			for own k, v of shutdownOrder
				if v.state != "stopped"
					log.debug "Service #{k} in state #{v.state} after shutdown loop, relooping"
					breakOut = false
			if breakOut
				break
		cb?()

	shutdownSync: () -> Sync () => @shutdown.sync @

# base class for all services
module.exports.Service = require "./service_template"

# register services
services = [
	new(require "./services/pulseaudio")
	new(require "./services/ts3client")
	new(require "./services/vlc")
	new(require "./services/xvfb")
	new(require "./services/xwm")
]
services.sort require("./service_depcomparer") # sort services by dependency
for service in services
	module.exports.register service

module.exports.services = services