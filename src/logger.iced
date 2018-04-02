winston = require "winston"
path = require "path"
config = require "./config"
merge = require "merge"
winstonCommon = require "winston/lib/winston/common"

winston.emitErrs = true

transports = []

# console logging
console.log "Minimal logging level for console is #{config.get("console-log-level")}"
transports.push new (winston.transports.Console)
	colorize: not config.get("json")
	silent: config.get("quiet") or config.get("silent") or false
	json: config.get("json") or false
	stringify: config.get("json") and config.get("json-stringify") or false
	timestamp: config.get("timestamp") or false
	debugStdout: not config.get("debug-stderr")
	prettyPrint: not config.get("json")
	level: config.get("console-log-level")

# file logging
if not config.get("disable-file-logging")
	transports.push new (winston.transports.File)
		filename: path.join config.get("log-path"), "#{config.get("environment")}.log"
		tailable: true
		zippedArchive: config.get("zip-logs") or false
		level: config.get("file-log-level")
	if config.get("json")
		transports.push new (winston.transports.File)
			filename: path.join config.get("log-path"), "#{config.get("environment")}.json"
			json: true
			tailable: true
			zippedArchive: config.get("zip-logs") or false
			level: config.get("file-log-level")

container = new (winston.Container)
	transports: transports

initialized_loggers = []

module.exports = (name, options) =>
	if not(name in initialized_loggers)
		logger = container.add name
		logger.addFilter (msg, meta, level) => "[#{name}] #{msg}"
		initialized_loggers.push name
		return logger

	container.get name