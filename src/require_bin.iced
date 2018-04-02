which = require("which").sync
path = require "path"
log = require("./logger")("RequireBin")

module.exports = (binName, doErrorIfNotFound) =>
	doErrorIfNotFound = true unless doErrorIfNotFound?

	# check if binary is findable from here
	if path.resolve(binName) == path.normalize(binName)
		# this is an absolute path
		return binName

	log.silly "Detecting #{binName}..."
	try
		binPath = which binName
		log.debug "#{binName} detected:", binPath
		return binPath
	catch err
		if doErrorIfNotFound
			log.error "#{binName} could not be found."
			throw new Error "#{binName} could not be found."
		else
			log.warn "#{binName} could not be found."
			return null
