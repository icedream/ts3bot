import Sync from 'sync'
import readline from 'readline'

import services from './services'
import getLogger from './logger'
import app from './app.iced'

log = getLogger('app')

# compatibility with Windows for interrupt signal
if process.platform == 'win32'
	rl = readline.createInterface(
		input: process.stdin
		output: process.stdout)
	rl.on 'SIGINT', ->
		process.emit 'SIGINT'

doShutdownAsync = (cb) ->
	log.info 'App shutdown starting...'
	app.shutdown ->
		log.info 'Services shutdown starting...'
		services.shutdown ->
			if cb and typeof cb == 'function'
				cb()
			return
		return
	return

process.on 'uncaughtException', (err) ->
	log.error 'Shutting down due to an uncaught exception!', err
	app.shutdownSync()
	process.exit 0xFF
	return

process.on 'exit', (e) ->
	log.debug 'Triggered exit', e
	app.shutdownSync()
	return

process.on 'SIGTERM', (e) ->
	log.debug 'Caught SIGTERM signal'
	app.shutdown ->
		process.exit 0
		return
	return

process.on 'SIGINT', ->
	log.debug 'Caught SIGINT signal'
	app.shutdown ->
		process.exit 0
		return
	return

process.on 'SIGHUP', ->
	log.debug 'Caught SIGHUP signal'
	app.shutdown ->
		process.exit 0
		return
	return

process.on 'SIGQUIT', ->
	log.debug 'Caught SIGQUIT signal'
	app.shutdown ->
		process.exit 0
		return
	return

process.on 'SIGABRT', ->
	log.debug 'Caught SIGABRT signal'
	app.shutdown ->
		process.exit 0
		return
	return
