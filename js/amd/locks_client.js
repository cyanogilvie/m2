/*global define */
/*jslint nomen: true, plusplus: true, white: true, browser: true, node: true, newcap: true, continue: true */

define([
	'dojo/_base/declare',
	'sop/signalsource',
	'sop/signal',
	'sop/gate',
	'sop/domino',
	'cflib/log',
	'tcl/list',
	'./promise'
], function(
	declare,
	Signalsource,
	Signal,
	Gate,
	Domino,
	log,
	tcllist,
	Promise
){
"use strict";

return declare([Signalsource], {
	heartbeat_interval: null,
	tag: null,
	connector: null,
	id: null, 

	_heartbeat_afterid: null,
	_lock_jmid: null,
	_lock_prev_seq: null,
	_promise: null,

	constructor: function(){
		if (this.tag === null) {
			throw new Error('Must supply tag');
		}
		if (this.connector === null) {
			throw new Error('Must supply connector');
		}
		if (this.id === null) {
			throw new Error('Must supply id');
		}

		this._signals.locked = new Signal({name: 'locked'});

		this.relock();
	},

	destroy: function() {
		this.unlock();
		// TODO: cancel heartbeat afterid
		this._heartbeat_afterid = null;
		this.connector = null;
	},

	relock: function() {
		var self, promise;

		var promise = this.promise = new Promise();

		if (this._signals.locked.state()) {
			return;
		}
		self = this;
		try {
			this.connector.req_async(this.tag, this.id, function(msg) {
				self._lock_cb(promise, msg);
			});
		} catch(err) {
			this._signals.locked.set_state(false);
			log.error('lock failed, could not get a lock - returned error '+err);
		}

		//TODO : setup heartbeat
		return promise;
	},

	lock_req: function(op, data, cb) {
		if (!this._signals.locked.state() || this._lock_jmid === null) {
			throw new Error('Can not apply action, no lock held');
		}
		this.connector.chan_req_async(this._lock_jmid, tcllist.array2list([op, data]), function(msg) {
			if (cb) {
				cb(msg);
			}
		});
	},

	unlock: function() {
		if (!this._signals.locked.state() || this._lock_jmid === null) {
			return;
		}

		this.connector.jm_disconnect(this._lock_jmid, this._lock_prev_seq);
		this._lock_jmid = null;
		this._lock_prev_seq = null;

		/*
			Normally here we would call :
			invoke_handlers lock_lost
			invoke_handlers lock_lost_detail msg.data
			*/

	},

	_lock_jm_update: function(data) {
		// Overide in derived class to handle app specific jm updates ??
		log.error('got jm update we were not expecting');
	},

	_lock_cb: function(promise, msg) {
		var jmid;

		jmid = msg.seq;

		switch (msg.type) {
			case 'pr_jm':
				if (this._lock_jmid !== null) {
					throw new Error('Unexpected pr_jm ('+jmid+'), already have lock_jmid ('+this._lock_jmid+')');
				}
				this._lock_jmid = msg.seq;
				this._lock_prev_seq = msg.prev_seq;
				this._signals.locked.set_state(true);
				promise.resolve(this);
				break;
			case 'jm':
				this._lock_jm_update(msg.data);
				break;
			case 'ack':
				break;
			case 'jm_can':
				if (this._lock_jmid !== null && jmid == this._lock_jmid) {
					this._lock_jmid = null;
					this._lock_prev_seq = null;
					this._signals.locked.set_state(false);
					promise.reject(msg.data);

					/*
					Normally here we would call :
					invoke_handlers lock_lost
					invoke_handlers lock_lost_detail msg.data
					*/
				} else {
					log.error('Unknown jmid cancelled: ('+jmid+')');
				}
				break;
			case 'nack':
				log.warning('lock failed: '+msg.data);
				this._signals.getItem('locked').set_state(false);
				promise.reject(msg.data);
				break;
			default:
				log.error('Unexpected type: '+msg.type);
				break;
		}
	},

	_setup_heartbeat: function(heartbeat) {
	},

	_send_heartbeat: function() {
	}
});
});

