// vim: ft=javascript foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
/*global Hash Signal log m2 serialize_tcl_list */

m2.locks_client = function(params) { //<<<
	this.heartbeat_interval = null;
	this.heartbeat_afterid = null;
	this.lock_jmid = null;
	this.lock_prev_seq = null;

	if (typeof params != 'undefined') {
		if (typeof params.tag != 'undefined') {
			this.tag = params.tag;
		} else {
			throw('Must specify tag');
		}
		if (typeof params.connector != 'undefined') {
			this.connector = params.connector;
		} else {
			throw('Must specify connector');
		}
		if (typeof params.id != 'undefined') {
			this.id = params.id;
		} else {
			throw('Must specify id');
		}
	}

	this._signals = new Hash();

	this._signals.setItem('locked', new Signal({name: 'locked'}));

	this.relock();
};

//>>>
m2.locks_client.prototype.destroy = function() { //<<<
	this.heartbeat_interval = null;
	this.heartbeat_afterid = null;
	this.lock_jmid = null;
	this.lock_prev_seq = null;
	this.tag = null;
	this.connector = null;
	this.id = null;
	this._signals = new Hash();
};

//>>>
m2.locks_client.prototype.signal_ref = function(name) { //<<<
	if (!this._signals.hasItem(name)) {
        throw('Signal "'+name+'" doesn\'t exist');
    }
    return this._signals.getItem(name);
};

//>>>
m2.locks_client.prototype.relock = function() { //<<<
	var self;
	if (this._signals.getItem('locked').state()) {
		throw('Already have a lock');
	}
	self = this;
	try {
		this.connector.req_async(this.tag, this.id, function(msg) {
				self._lock_cb(msg);
		});
	} catch(e) {
		this._signals.getItem('locked').set_state('false');
		log.error('lock failed, could not get a lock - returned error '+e);
	}
	this._signals.getItem('locked').set_state('true');

	//TODO : setup heartbeat
};

//>>>
m2.locks_client.prototype.lock_req = function(op, data, cb) { //<<<
	if (!this._signals.getItem('locked').state() || this.lock_jmid === null) {
		throw('Can not apply action, no lock held');
	}
	this.connector.chan_req_async(this.lock_jmid, serialize_tcl_list([op, data]), function(msg) {
			if (cb != 'undefined') {
				cb.call(null, msg);
			}
	});
};

//>>>
m2.locks_client.prototype.unlock = function() { //<<<
	if (!this._signals.getItem('locked').state() || this.lock_jmid === null) {
		throw('No lock held');
	}

	this.connector.jm_disconnect(this.lock_jmid, this.lock_prev_seq);
	this.lock_jmid = null;
	this.lock_prev_seq = null;

	/*
		Normally here we would call :
		invoke_handlers lock_lost
		invoke_handlers lock_lost_detail msg.data
		*/

};

//>>>
m2.locks_client.prototype._lock_jm_update = function(data) { //<<<
	// Overide in derived class to handle app specific jm updates ??
	log.error('got jm update we were not expecting');
};

//>>>
m2.locks_client.prototype._lock_cb = function(msg) { //<<<
	var jmid;

	jmid = msg.seq;

	switch (msg.type) {
		case 'pr_jm':
			if (this.lock_jmid !== null) {
				throw('Unexpected pr_jm ('+jmid+'), already have lock_jmid ('+this.lock_jmid+')');
			}
			this.lock_jmid = msg.seq;
			this.lock_prev_seq = msg.prev_seq;
			this._signals.getItem('locked').set_state(true);
			break;
		case 'jm':
			this._lock_jm_update(msg.data);
			break;
		case 'jm_can':
			if (this.lock_jmid !== null && jmid == this.lock_jmid) {
				this.lock_jmid = null;
				this.lock_prev_seq = null;
				this._signals.getItem('locked').set_state(false);

				/*
				   Normally here we would call :
				   invoke_handlers lock_lost
				   invoke_handlers lock_lost_detail msg.data
				 */
			} else {
				log.error('Unknown jmid cancelled: ('+jmid+')');
			}
			break;
		default:
			log.error('Unexpected type: '+msg.type);
			break;
	}
};

//>>>
m2.locks_client.prototype._setup_heartbeat = function(heartbeat) { //<<<
};

//>>>
m2.locks_client.prototype._send_heartbeat = function() { //<<<
};

//>>>
