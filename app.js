require("iced-coffee-script/register");
Sync = require("sync");

var services = require("./services");

var getLogger = require("./logger");
var log = getLogger("app");

// compatibility with Windows for interrupt signal
if (process.platform === "win32") {
	var rl = require("readline").createInterface({
		input: process.stdin,
		output: process.stdout
	});
	rl.on("SIGINT", function() {
		return process.emit("SIGINT");
	});
}

app = require("./app.iced");

doShutdownAsync = function(cb) {
	log.info("App shutdown starting...");
	app.shutdown(function() {
		log.info("Services shutdown starting...");
		services.shutdown(function() {
			if (cb && typeof cb === "function")
				cb();
		});
	});
};

process.on("uncaughtException", function(err) {
	log.fatal("Shutting down due to an uncaught exception!", err);
	app.shutdownSync();
});

process.on("exit", function(e) {
	log.debug("Triggered exit", e);
	app.shutdownSync();
});

process.on("SIGTERM", function(e) {
	log.debug("Caught SIGTERM signal");
	app.shutdown();
});

process.on("SIGINT", function() {
	log.debug("Caught SIGINT signal");
	app.shutdown();
});

process.on("SIGHUP", function() {
	log.debug("Caught SIGHUP signal");
	app.shutdown();
});

process.on("SIGQUIT", function() {
	log.debug("Caught SIGQUIT signal");
	app.shutdown();
});

process.on("SIGABRT", function() {
	log.debug("Caught SIGABRT signal");
	app.shutdown();
});
