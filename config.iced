nconf = require "nconf"
path = require "path"
merge = require "merge"
pwgen = require "password-generator"

console.log "Loading configuration..."

# Build configuration object from input
nconf.env [ "NODE_ENV", "PULSE_BINARY" ]
nconf.argv()
nconf.file path.join(process.env["HOME"], ".ts3bot", "config.json")
nconf.defaults
	# read http://stackoverflow.com/q/12252043 on why I'm using .trim here
	"environment": process.env.NODE_ENV?.trim() or "development"
	"log-path": "."
	"vlc-host": "0.0.0.0"
	"vlc-port": 8080
	"vlc-password": pwgen()
	"nickname": "TS3Bot"
	"ts3-install-path": path.resolve __dirname, "..", "ts3client"
	"ts3-config-path": path.join process.env.HOME, ".ts3client"
	"xvfb-resolution": "800x600x16"
	"console-log-level": "info"
	"file-log-level": "debug"
	"PULSE_BINARY": "pulseaudio"

# Validate configuration
if not nconf.get("ts3-server")
	throw new Error "You need to provide a TeamSpeak3 server URL (starts with ts3server:// and can be generated from any TS3 client GUI)."

if nconf.get("nickname")? and (nconf.get("nickname").length < 3 or nconf.get("nickname").length > 30
	throw new Error "Nickname must be between 3 and 30 characters long."

console.log "Configuration loaded."

if nconf.get "dump-config"
	console.log nconf.get()
	process.exit 0

module.exports = merge true, nconf,
	isProduction: -> @get("environment").toUpperCase() == "PRODUCTION"