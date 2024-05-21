const debug = require("debug");

debug.log = console.log.bind(console);

/**
 * Creates a logger for a module.
 * @example
 *   const log = require("../utils/logger")("task:OSwap");
 *   log('something interesting happened');
 * @param {string} module name of the module to log for. eg "task:OSwap:snap"
 */
const logger = (module) => debug(`origin:${module}`);

module.exports = logger;
