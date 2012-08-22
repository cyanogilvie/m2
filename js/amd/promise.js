/*global define */
/*jslint nomen: true, plusplus: true, white: true, browser: true, node: true, newcap: true, continue: true */

// Designed to be API compatible with dojo's Promise, so that apps that use
// dojo can use the Deferred machinery on our promises

define([
	'dojo/_base/declare',
	'cflib/log'
], function(
	declare,
	log
){
"use strict";

return declare([], {
	constructor: function(params) {
		params = params || {};

		this.status = 'WAITING';
		this.cancelled = false;
		this.fulfilled = false;
		this.resolved_cbs = [];
		this.err_cbs = [];
		this.result = null;
		this.err = null;
	},

	then: function(callback, errback, progback) {
		switch (this.status) {
			case 'WAITING':
				if (callback) {
					this.resolved_cbs.push(callback);
				}
				if (errback) {
					this.err_cbs.push(errback);
				}
				// We don't emit progress callbacks
				break;

			case 'RESOLVED':
				callback(this.result);
				break;

			case 'REJECTED':
				errback(this.err);
				break;

			default:
				throw new Error('Bad promise status: "'+this.status+'"');
		}
	},

	cancel: function(reason) {
		if (this.cancelled) {
			return;
		}
		this.cancelled = true;
		if (!this.fulfilled) {
			this.reject('Cancelled');
		}
	},

	isResolved: function() {
		return this.status === 'RESOLVED';
	},

	isRejected: function() {
		return this.status === 'REJECTED';
	},

	isFulfilled: function() {
		return !!this.fulfilled;
	},

	isCancelled: function() {
		return this.cancelled;
	},

	always: function(callbackOrErrback) {
	},

	otherwise: function(errback) {
	},

	trace: function() {
		return this;
	},

	traceRejected: function() {
		return this;
	},

	toString: function() {
		return "[object m2.promise]";
	},

	resolve: function(value, strict) {
		var i;
		if (!this.fulfilled) {
			this.result = value;
			this.status = 'RESOLVED';
			this.fulfilled = true;
			if (!this.cancelled) {
				for (i=0; i<this.resolved_cbs.length; i++) {
					try {
						this.resolved_cbs[i].call(null, this.result);
					} catch(error) {
						log.error('Error calling promise resolve callback: '+error);
					}
				}
			}
		} else if (strict === true){
			throw new Error('Already fulfilled');
		} else {
			return this;
		}
	},

	reject: function(error) {
		var i;
		if (!this.fulfilled) {
			this.err = error;
			this.status = 'REJECTED';
			this.fulfilled = true;
			if (!this.cancelled) {
				for (i=0; i<this.err_cbs.length; i++) {
					try {
						this.err_cbs[i].call(null, error);
					} catch(err) {
						log.error('Error calling promise error callback: '+err);
					}
				}
			}
		}
	}
});
});


