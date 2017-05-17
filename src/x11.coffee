import Sync from 'sync'
import { spawn } from 'child_process'
import StreamSplitter from 'stream-splitter'

import getLogger from './logger'
import services from './services'
import require_bin from './require_bin'

log = getLogger "X11tools"
xdotoolBinPath = require_bin "xdotool", false

# Just some tools to work with the X11 windows
module.exports =
	getWindowIdByProcessId: (pid, cb) ->
		wid = null

		# Return null instantly if xdotool is not available
		if not xdotoolBinPath?
			cb? new Error "xdotool is not available"
			return

		# We provide --name due to the bug mentioned at
		# https://github.com/jordansissel/xdotool/issues/14
		xdoproc = spawn xdotoolBinPath, [
			"search", "--any", "--pid", pid, "--name", "xdosearch" ],
			env:
				DISPLAY: process.env.DISPLAY
				XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR
		stdoutTokenizer = xdoproc.stdout.pipe StreamSplitter "\n"
		stdoutTokenizer.encoding = "utf8"
		stdoutTokenizer.on "token", (token) ->
			token = token.trim() # get rid of \r
			newWid = parseInt(token)
			if newWid != 0 and wid == null
				wid = newWid
		stderrTokenizer = xdoproc.stderr.pipe StreamSplitter "\n"
		stderrTokenizer.encoding = "utf8"
		stderrTokenizer.on "token", (token) ->
			token = token.trim() # get rid of \r
			log.warn token
		await xdoproc.on "exit", defer(e)

		if e.code
			log.error "Failed to find window ID, error code #{e.code}"
			err = new Error "Failed to find window ID."
			cb? err
			return

		cb? null, parseInt(wid)

	getWindowIdByProcessIdSync: (pid) ->
		Sync() -> @getWindowIdByProcessId.sync @, pid

	sendKeys: (wid, keys, cb) ->
		# Do not bother trying if xdotool is not available
		if not xdotoolBinPath?
			cb? new Error "xdotool not available."
			return

		# a window manager needs to be running for windowactivate to work
		xwmService = services.find("XWindowManager")
		if xwmService.state != "started"
			await xwmService.start defer(err)
			if err
				cb? new Error "Could not start a window manager."
				return

		xdoproc = spawn xdotoolBinPath, [
			"windowactivate",
			"--sync",
			wid,
			"key",
			"--clearmodifiers",
			"--delay", "100" ].concat(keys),
			env:
				DISPLAY: process.env.DISPLAY
				XDG_RUNTIME_DIR: process.env.XDG_RUNTIME_DIR
		stdoutTokenizer = xdoproc.stdout.pipe StreamSplitter "\n"
		stdoutTokenizer.encoding = "utf8"
		stdoutTokenizer.on "token", (token) ->
			token = token.trim() # get rid of \r
			log.debug token
		stderrTokenizer = xdoproc.stderr.pipe StreamSplitter "\n"
		stderrTokenizer.encoding = "utf8"
		stderrTokenizer.on "token", (token) ->
			token = token.trim() # get rid of \r
			log.warn token
		await xdoproc.on "exit", defer(e)

		err = null
		if e.code
			log.error "Failed to send keys, error code #{e.code}"
			err = new Error "Failed to send keys."
		cb? err

	sendKeysSync: (keys) => Sync () => @sendKeys.sync @, keys
