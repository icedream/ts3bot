module.exports = (a, b) ->
	if a.dependencies.indexOf(b.name) >= 0
		return -1; # a before b
	if b.dependencies.indexOf(a.name) >= 0
		return 1; # a after b
	return 0 # does not matter
