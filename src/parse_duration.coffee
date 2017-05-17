import parseDuration from 'parse-duration'
import { named as namedRegex } from 'named-regexp'

durationRegex = namedRegex /^(((:<h>[0-9]{0,2}):)?(:<m>[0-9]{0,2}):)?(:<s>[0-9]{0,2})(:<ms>\.[0-9]*)?$/

module.exports = (str) ->
	# check if this is in the colon-separated format
	if str.indexOf(":") > -1 and str.match durationRegex
		m = durationRegex.exec(str).matches
		return m["ms"] + m["s"]*60 + m["m"]*(60*60) + m["h"]*(60*60*60)

	parseDuration str
