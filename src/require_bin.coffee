import { sync as which } from 'which'
import path from 'path'

import getLogger from './logger'

log = getLogger "RequireBin"

module.exports = (binName, doErrorIfNotFound) ->
	doErrorIfNotFound = true unless doErrorIfNotFound?

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
		if doErrorIfNotFound
			log.error "#{binName} could not be found."
			throw new Error "#{binName} could not be found."
		else
			log.warn "#{binName} could not be found."
			return null
