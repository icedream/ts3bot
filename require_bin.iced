which = require("which").sync
path = require "path"
log = require("./logger")("RequireBin")

module.exports = (binName) =>
	# check if xvfb is findable from here
	if path.resolve(binName) == path.normalize(binName)
		# this is an absolute path
		return binName

	log.silly "Detecting #{binName}..."
	try
		binPath = which binName
		log.debug "#{binName} detected:", binPath
		return binPath
	catch err
		log.error "#{binName} could not be found.", err
		throw new Error "#{binName} could not be found."
