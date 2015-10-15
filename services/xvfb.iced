Xvfb = require("xvfb")
log = require("../logger")("Xvfb")
config = require("../config")
services = require("../services")
require_bin = require("../require_bin")

require_bin "Xvfb"

module.exports = class XvfbService extends services.Service
	constructor: -> super "Xvfb",
		start: (cb) ->
			if @instance
				cb? null, @instance
				return

			instance = new Xvfb
				detached: true
				reuse: true
				silent: false
				timeout: 5000
				xvfb_args: [
					"-screen"
					"0"
					config.get("xvfb-resolution")
					"-ac"
				]
			await instance.start defer(err)

			if err
				cb? err, null

			@instance = instance

			cb? null, @instance

		stop: (cb) ->
			if not @instance
				cb?()
				return

			await @instance.stop defer(err)
			if err
				cb? err, null

			@instance = null
			cb?()
