/*global Base64 Hash Signal Utf8 cfcrypto evlog jsSocket log parse_tcl_list serialize_tcl_list window */

function m2() {} // namespace


m2.api = function(params) { //<<<
	if (typeof params == 'undefined') {
		return;
	}
	// Public
	this.host = null;
	this.port = null;
	if (typeof params.host != 'undefined') {
		this.host = params.host;
	}
	if (typeof params.port != 'undefined') {
		this.port = params.port;
	}
	if (this.host === null) {
		this.host = window.location.hostname;
	}
	if (this.port === null) {
		this.port = 5301;
	}

	// Private
	var self;
	self = this;
	this._unique_id = 0;
	this._handlers = new Hash();
	this._event_handlers = new Hash();
	this._pending = new Hash();
	this._ack_pend = new Hash();
	this._jm = new Hash();
	this._jm_prev_seq = new Hash();
	this._socket = null;
	this._signals = new Hash();
	this._svcs = new Hash();
	this._svc_signals = new Hash();
	this._defrag_buf = new Hash();
	this._msgid_seq = 0;
	this._queues = new Hash();
	this._jm_keys = new Hash();
	this._key_schedules = new Hash();
	this._pending_keys = new Hash();
	var t = [];
	if (typeof t.indexOf == 'undefined') {
		this._arr_indexOf = function(arr, item) {
			var i;
			//log.debug('Using custom _arr_indexOf');
			for (i=0; i<arr.length; i++) {
				if (item == arr[i]) {
					return i;
				}
			}
			return -1;
		};
	} else {
		this._arr_indexOf = function(arr, item) {
			return arr.indexOf(item);
		};
	}

	log.debug('attempting to connect to m2_node on ('+this.host+') ('+this.port+')');
	this._signals.setItem('connected', new Signal({
		name: 'connected'
	}));

	this._socket = new jsSocket({
		host: this.host,
		port: this.port
	});

	this._socket.received = function(data) {
		self._receive_raw(data);
	};
	this._socket.signals.connected.attach_output(function(newstate) {
		self._socket_connected_changed(newstate);
	});
};

//>>>
m2.api.prototype.destroy = function() { //<<<
	this._socket.close();
	return null;
};

//>>>

// Public
m2.api.prototype.signal_ref = function(name) { //<<<
	if (!this._signals.hasItem(name)) {
		throw('Signal "'+name+'" doesn\'t exist');
	}
	return this._signals.getItem(name);
};

//>>>
m2.api.prototype.svc_signal = function(svc) { //<<<
	var sig;
	if (!this._svc_signals.hasItem(svc)) {
		sig = new Signal({
			name: 'svc_avail_'+svc
		});
		sig.set_state(this.svc_avail(svc));
		this._svc_signals.setItem(svc, {
			sig: sig,
			svc: svc
		});
	}
	return this._svc_signals.getItem(svc).sig;
};

//>>>
m2.api.prototype.svc_avail = function(svc) { //<<<
	return this._svcs.hasItem(svc);
};

//>>>
m2.api.prototype.req = function(svc, data, cb, withkey) { //<<<
	var seq;

	seq = this._unique_id++;

	if (typeof withkey != 'undefined') {
		data = this.encrypt(withkey, data);
	}

	this._send({
		svc:	svc,
		type:	'req',
		seq:	seq,
		data:	data
	});

	window.udata = Utf8.encode(data);
	this._pending.setItem(seq, cb);
	this._ack_pend.setItem(seq, 1);
	this._jm.setItem(seq, 0);

	return seq;
};

//>>>
m2.api.prototype.rsj_req = function(jm_seq, data, cb) { //<<<
	var seq, e_data, key;

	seq = this._unique_id++;

	if (this._jm_keys.hasItem(jm_seq)) {
		key = this._jm_keys.getItem(jm_seq);
		this._pending_keys.setItem(seq, key);
		e_data = this.encrypt(key, data);
	} else {
		e_data = data;
	}

	this._send({
		svc:		'',
		type:		'rsj_req',
		seq:		seq,
		prev_seq:	jm_seq,
		data:		e_data
	});

	this._pending.setItem(seq, cb);
	this._ack_pend.setItem(seq, 1);
	this._jm.setItem(seq, 0);

	return seq;
};

//>>>
m2.api.prototype.jm_disconnect = function(jm_seq, prev_seq) { //<<<
	this._send({
		svc:		'',
		type:		'jm_disconnect',
		seq:		jm_seq,
		prev_seq:	prev_seq,
		data:		''
	});

	if (this._jm_prev_seq.hasItem(jm_seq)) {
		var idx, pseq_tmp, i, new_prev_seqs, old_prev_seqs;
		pseq_tmp = this._jm_prev_seq.getItem(jm_seq);
		idx = this._arr_indexOf(pseq_tmp, prev_seq);

		if (idx == -1) {
			// prev_seq invalid
		} else {
			this._jm.setItem(prev_seq, this._jm.getItem(prev_seq) - 1);
			if (this._jm.getItem(prev_seq) <= 0) {
				this._pending.removeItem(prev_seq);
				this._jm.removeItem(prev_seq);
			}
			new_prev_seqs = [];
			old_prev_seqs = this._jm_prev_seq.getItem(jm_seq);
			for (i=0; i<old_prev_seqs.length; i++) {
				if (old_prev_seqs[i] != prev_seq) {
					new_prev_seqs.push(old_prev_seqs[i]);
				}
			}
			if (new_prev_seqs.length > 0) {
				this._jm_prev_seq.setItem(jm_seq, new_prev_seqs);
			} else {
				this._jm_prev_seq.removeItem(jm_seq);
			}
		}
	} else {
		// Can't find this._jm_prev_seq(jm_seq)
	}
};

//>>>
m2.api.prototype.register_jm_key = function(jm_seq, key) { //<<<
	//log.debug('Registering jm_key for '+jm_seq+', base64: '+Base64.encode(key));
	this._jm_keys.setItem(jm_seq, key);
};

//>>>
m2.api.prototype.encrypt = function(key, data) { //<<<
	var ks, iv, csprng;

	if (!this._key_schedules.hasItem(key)) {
		this._key_schedules.setItem(key, new cfcrypto.blowfish(key));
	}
	ks = this._key_schedules.getItem(key);
	csprng = new cfcrypto.csprng();
	iv = csprng.getbytes(8);

	return iv+ks.encrypt_cbc(data, iv);
};

//>>>
m2.api.prototype.decrypt = function(key, data, hint) { //<<<
	var ks, iv, rest;

	if (!this._key_schedules.hasItem(key)) {
		this._key_schedules.setItem(key, new cfcrypto.blowfish(key));
	}
	ks = this._key_schedules.getItem(key);
	iv = data.substr(0, 8);
	rest = data.substr(8);

	//log.debug('Decrypting msg with iv: '+Base64.encode(iv)+', key: '+Base64.encode(key), ', hint: '+hint);

	return ks.decrypt_cbc(rest, iv);
};

//>>>
m2.api.prototype.listen_event = function(event, cb) { //<<<
	var existing;
	if (this._event_handlers.hasItem(event)) {
		existing = this._event_handlers.getItem(event);
	} else {
		existing = [];
	}
	existing.push(cb);
	this._event_handlers.setItem(event, existing);
};

//>>>

// Private
m2.api.prototype._gotMsg = function(reqseq, type, payload) { //<<<
	if (this._handlers.hasItem(reqseq)) {
		this._handlers.getItem(reqseq)(type, payload);
		if (type == 'ack' || type == 'nack') {
			this._handlers.removeItem(reqseq);
		}
	} else {
	}
};

//>>>
m2.api.prototype._set_default_msg_fields = function(msg) { //<<<
	if (msg.svc === undefined)		{msg.svc		= 'sys';}
	if (msg.type === undefined)		{msg.type		= 'req';}
	if (msg.seq === undefined)		{msg.seq		= '';}
	if (msg.prev_seq === undefined)	{msg.prev_seq	= '0';}
	if (msg.meta === undefined)		{msg.meta		= '';}
	if (msg.oob_type === undefined)	{msg.oob_type	= '1';}
	if (msg.oob_data === undefined)	{msg.oob_data	= '1';}
};

//>>>
m2.api.prototype._receive_msg = function(msg_raw) { //<<<
	var lineend, pre_raw, pre, fmt, hdr_len, data_len, hdr, data, ofs, msg;
	//log.debug('received complete message: ('+msg_raw+')');

	lineend = msg_raw.indexOf("\n");
	if (lineend == -1) {
		throw('corrupt m2 message header: '+msg_raw);
	}
	pre_raw = msg_raw.substr(0, lineend);
	pre = parse_tcl_list(pre_raw);
	fmt = pre[0];
	if (fmt != 1) {
		throw('Cannot parse m2 message serialization format: ('+fmt+')');
	}
	hdr_len = Number(pre[1]);
	data_len = Number(pre[2]);
	hdr = parse_tcl_list(msg_raw.substr(lineend + 1, hdr_len));
	ofs = lineend + 1 + hdr_len;
	/*
	var i;
	for (i=0; i<hdr.length; i++) {
		log.debug('hdr: '+i+' = ('+hdr[i]+')');
	}
	*/
	data = msg_raw.substr(ofs, data_len);
	//log.debug('ofs: '+ofs+', data_len: '+data_len+', data: '+data);
	//log.debug('msg_raw.substr('+ofs+'): ('+msg_raw.substr(ofs)+')');
	msg = {
		'svc':		hdr[0],
		'type':		hdr[1],
		'seq':		hdr[2],
		'prev_seq':	hdr[3],
		'meta':		hdr[4],
		'oob_type':	hdr[5],
		'oob_data':	hdr[6],
		'data':		data
	};
	this._got_msg(msg);
};

//>>>
m2.api.prototype._svc_avail = function(new_svcs) { //<<<
	var i, keys, inf, have_svc;

	for (i=0; i<new_svcs.length; i++) {
		this._svcs.setItem(new_svcs[i], true);
	}

	keys = this._svc_signals.keys();
	for (i=0; i<keys.length; i++) {
		inf = this._svc_signals.getItem(keys[i]);
		have_svc = this._svcs.hasItem(inf.svc);
		inf.sig.set_state(have_svc);
	}

	this._dispatch_event('svc_avail_changed', this._svcs);
};

//>>>
m2.api.prototype._svc_revoke = function(revoked_svcs) { //<<<
	var i, keys, inf, have_svc;

	for (i=0; i<revoked_svcs.length; i++) {
		if (this._svcs.hasItem(revoked_svcs[i])) {
			this._svcs.removeItem(revoked_svcs[i]);
		}
	}

	keys = this._svc_signals.keys();
	for (i=0; i<keys.length; i++) {
		inf = this._svc_signals.getItem(keys[i]);
		have_svc = this._svcs.hasItem(inf.svc);
		inf.sig.set_state(have_svc);
	}

	this._dispatch_event('svc_avail_changed', this._svcs);
};

//>>>
m2.api.prototype._jm_can = function(msg) { //<<<
	var prev_seq_arr, i, tmp, prev_seq, cb;

	if (this._jm_prev_seq.hasItem(msg.seq)) {
		this._jm_prev_seq.removeItem(msg.seq);
	}

	prev_seq_arr = parse_tcl_list(msg.prev_seq);

	for (i=0; i<prev_seq_arr.length; i++) {
		prev_seq = prev_seq_arr[i];
		tmp = this._jm.getItem(prev_seq);
		tmp--;
		this._jm.setItem(prev_seq, tmp);
		if (this._pending.hasItem(prev_seq)) {
			cb = this._pending.getItem(prev_seq);
			if (cb !== '') {
				try {
					cb(msg, prev_seq);
				} catch(e) {
					log.error('error calling callback for jm_can: '+e);
				}
			}
		}
		if (this._jm.getItem(prev_seq) <= 0) {
			if (this._pending.hasItem(prev_seq)) {
				this._pending.removeItem(prev_seq);
			}
			if (this._jm.hasItem(prev_seq)) {
				this._jm.removeItem(prev_seq);
			}
		}
	}
};

//>>>
m2.api.prototype._response = function(msg) { //<<<
	//log.debug('_response: ', msg);
	var prev_seq_arr, i, prev_seq, cb, msgcopy;

	msgcopy = msg;
	prev_seq_arr = parse_tcl_list(msg.prev_seq);
	for (i=0; i<prev_seq_arr.length; i++) {
		prev_seq = prev_seq_arr[i];
		msgcopy.prev_seq = prev_seq;
		if (this._pending.hasItem(prev_seq)) {
			cb = this._pending.getItem(prev_seq);
			if (cb !== '') {
				try {
					//log.debug('Calling callback with: ', msgcopy);
					cb(msgcopy);
				} catch (e) {
					log.error('error calling callback for response type: '+msg.type+': '+e);
				}
			} else {
				log.error('No callback registered for prev_seq: '+prev_seq);
			}
		} else {
			log.error('No _pending entry for prev_seq: '+prev_seq);
		}
		if (!this._jm.hasItem(prev_seq)) {
			continue;
		}
		if (
			this._jm.getItem(prev_seq) <= 0 &&
			!this._ack_pend.hasItem(prev_seq)
		) {
			if (this._pending.hasItem(prev_seq)) {
				this._pending.removeItem(prev_seq);
			}
			if (this._jm.hasItem(prev_seq)) {
				this._jm.removeItem(prev_seq);
			}
		}
	}
};

//>>>
m2.api.prototype._evlog_msg = function(msg) { //<<<
	return serialize_tcl_list([
		'svc',		msg.svc,
		'type',		msg.type,
		'seq',		msg.seq,
		'prev_seq',	msg.prev_seq,
		'meta',		msg.meta,
		'oob_type',	msg.oob_type,
		'oob_data',	msg.oob_data,
		'data',		msg.data
	]);
};

//>>>
m2.api.prototype._got_msg = function(msg) { //<<<
	/*
	log.debug('got m2 msg:');
	log.debug('msg.svc: ('+msg.svc+')');
	log.debug('msg.type: ('+msg.type+')');
	log.debug('msg.seq: ('+msg.seq+')');
	log.debug('msg.prev_seq: ('+msg.prev_seq+')');
	log.debug('msg.meta: ('+msg.meta+')');
	log.debug('msg.oob_type: ('+msg.oob_type+')');
	log.debug('msg.oob_data: ('+msg.oob_data+')');
	log.debug('msg.data: ('+msg.data+')');
	*/
	evlog.event('m2.receive_msg', serialize_tcl_list([
		'from', this.host+':'+this.port,
		'msg', this._evlog_msg(msg)
	]));

	// Decrypt any encrypted data, store jm_keys for new jm channels <<<
	switch (msg.type) {
		case 'ack':
			this._ack_pend.removeItem(msg.prev_seq);
			if (this._pending_keys.hasItem(msg.prev_seq)) {
				msg.data = this.decrypt(this._pending_keys.getItem(msg.prev_seq), msg.data, 'ack of '+msg.prev_seq);
				this._pending_keys.removeItem(msg.prev_seq);
			}
			break;

		case 'nack':
			this._ack_pend.removeItem(msg.prev_seq);
			this._pending_keys.removeItem(msg.prev_seq);
			break;

		case 'pr_jm':
			this._jm.setItem(msg.prev_seq, this._jm.getItem(msg.prev_seq) + 1);

			if (!this._jm_prev_seq.hasItem(msg.seq)) {
				this._jm_prev_seq.setItem(msg.seq, [msg.prev_seq]);
			} else if (this._arr_indexOf(this._jm_prev_seq.getItem(msg.seq), msg.prev_seq) == -1) {
				var t;
				t = this._jm_prev_seq.getItem(msg.seq);
				if (typeof t.push == 'undefined') {
					log.error('something went badly wrong with jm_prev_seq('+msg.seq+'): ', t);
				} else {
					t.push(msg.prev_seq);
				}
				/*
				this._jm_prev_seq.setItem(msg.seq,
					this._jm_prev_seq.getItem(msg.seq).push(msg.prev_seq));
				*/
			}

			if (this._pending_keys.hasItem(msg.prev_seq)) {
				msg.data = this.decrypt(this._pending_keys.getItem(msg.prev_seq), msg.data, 'pr_jm for '+msg.seq+', resp to '+msg.prev_seq);
				if (!this._jm_keys.hasItem(msg.seq)) {
					if (msg.data.length != 56) {
						log.warning('pr_jm: dubious looking key: ('+Base64.encode(msg.data)+')');
					}
					this.register_jm_key(msg.seq, msg.data);
					return;
				} else {
					if (msg.data.length == 56) {
						if (msg.data === this._jm_keys.getItem(msg.seq)) {
							log.warning('pr_jm: jm('+msg.seq+') got channel key setup twice!');
							return;
						} else {
							log.warning('pr_jm: got what may be another key on this jm ('+msg.seq+'), that differs from the first');
						}
					}
				}
			}
			break;

		case 'jm':
			if (this._jm_keys.hasItem(msg.seq)) {
				msg.data = this.decrypt(this._jm_keys.getItem(msg.seq), msg.data, 'jm '+msg.seq);
			}
			break;

		case 'jm_req':
			if (this._jm_keys.hasItem(msg.prev_seq)) {
				msg.data = this.decrypt(this._jm_keys.getItem(msg.prev_seq), msg.data);
			}
			break;
	}
	// Decrypt any encrypted data, store jm_keys for new jm channels >>>

	switch (msg.type) {
		case 'svc_avail':
			this._svc_avail(parse_tcl_list(msg.data));
			break;

		case 'svc_revoke':
			this._svc_revoke(parse_tcl_list(msg.data));
			break;

		case 'jm_can':
			this._jm_can(msg);
			break;

		case 'jm_req':
			// TODO
			break;

		case 'pr_jm':
		case 'ack':
		case 'nack':
		case 'jm':
			this._response(msg);
			break;

		default:
			log.error('Invalid msg.type: ('+msg.type+')');
			var key;
			for (key in msg) {
				if (msg.hasOwnProperty(key)) {
					log.error('msg.'+key+': ('+msg[key]+')');
				}
			}
			break;
	}
};

//>>>
m2.api.prototype._serialize_msg = function(msg) { //<<<
	var hdr, sdata, udata;

	hdr = serialize_tcl_list([
		msg.svc,
		msg.type,
		msg.seq,
		msg.prev_seq,
		msg.meta,
		msg.oob_type,
		msg.oob_data
	]);
	//log.debug('serialized msg hdr: ('+hdr+'), msg.seq: ('+msg.seq+')');
	udata = Utf8.encode(msg.data);
	//udata = msg.data;
	//window.udata = udata;
	sdata = serialize_tcl_list([
		'1',
		hdr.length,
		udata.length
	]);
	sdata += '\n' + hdr + udata;

	return sdata;
};

//>>>
m2.api.prototype._send = function(msg) { //<<<
	var sdata;

	//console.log('Got request to send msg: ', msg);
	this._set_default_msg_fields(msg);
	sdata = this._serialize_msg(msg);
	this._enqueue(sdata, msg);
};

//>>>
m2.api.prototype._receive_fragment = function(msgid, is_tail, frag) { //<<<
	var complete, so_far;
	//log.debug('_receive_fragment: msgid: ('+msgid+'), is_tail: ('+is_tail+'), frag: ('+frag+')');
	//log.debug('_receive_fragment: msgid: ('+msgid+'), is_tail: ('+is_tail+'), frag length: ('+frag.length+')');
	if (this._defrag_buf.hasItem(msgid)) {
		so_far = this._defrag_buf.getItem(msgid);
	} else {
		so_far = '';
	}
	so_far += frag;
	if (is_tail) {
		complete = so_far;
		this._defrag_buf.removeItem(msgid);
		this._receive_msg(Utf8.decode(complete));
	} else {
		this._defrag_buf.setItem(msgid, so_far);
	}
};

//>>>
m2.api.prototype._receive_raw = function(packet) { //<<<
	//packet = Utf8.decode(packet_base64);
	//log.debug('_queue_receive_raw: ('+packet+')');
	var lineend, head, msgid, is_tail, fragment_len, frag, rest;
	rest = packet;
	//log.debug('packet.length: '+packet.length);
	while (rest.length > 0) {
		//log.debug('rest.length: '+rest.length);
		lineend = rest.indexOf("\n");
		if (lineend == -1) {
			throw('corrupt fragment header: '+rest);
		}
		//log.debug('header: '+rest.substr(0, lineend));
		head = parse_tcl_list(rest.substr(0, lineend));
		msgid = Number(head[0]);
		//is_tail = Boolean(head[1]);
		//is_tail = Boolean(Number(head[1]));
		/*
		if (Number(head[1]) === 0) {
			is_tail = false;
		} else {
			is_tail = true;
		}
		*/
		is_tail = Boolean(Number(head[1]));
		fragment_len = Number(head[2]);
		frag = rest.substr(lineend + 1, fragment_len);
		//log.debug('fragment_len: '+fragment_len+', frag.length: '+frag.length);
		if (fragment_len !== frag.length) {
			throw('Fragment length mismatch: expecting '+fragment_len+', got: '+frag.length);
		}
		//rest = rest.substr(lineend + 1 + fragment_len);
		rest = rest.substr(lineend + 1 + fragment_len);
		this._receive_fragment(msgid, is_tail, frag);
	}
};

//>>>
m2.api.prototype._enqueue = function(sdata, msg) { //<<<
	var msgid, payload;
	/* ----- Queueing requires that we get writable notifications -----
	var target, msgid, target_queue;

	target = this.assign(msg);
	msgid = this._msgid_seq++;
	if (!this._queues.hasItem(target)) {
		target_queue = [];
	} else {
		target_queue = this._queues.getItem(target);
	}
	target_queue.push([msgid, sdata]);
	this._queues.setItem(target, target_queue);
	*/

	/*
	log.debug('sending msg:');
	log.debug('msg.svc: ('+msg.svc+')');
	log.debug('msg.type: ('+msg.type+')');
	log.debug('msg.seq: ('+msg.seq+')');
	log.debug('msg.prev_seq: ('+msg.prev_seq+')');
	log.debug('msg.meta: ('+msg.meta+')');
	log.debug('msg.oob_type: ('+msg.oob_type+')');
	log.debug('msg.oob_data: ('+msg.oob_data+')');
	log.debug('msg.data: ('+msg.data+')');
	*/

	msgid = this._msgid_seq++;

	payload = String(msgid)+' 1 '+sdata.length+'\n'+sdata;
	//payload = Utf8.encode(String(msgid)+'\n'+sdata);
	this._socket.send(payload);

	evlog.event('m2.queue_msg', serialize_tcl_list([
		'to', this.host+':'+this.port,
		'msg', this._evlog_msg(msg)
	]));
};

//>>>
m2.api.prototype._socket_connected_changed = function(newstate) { //<<<
	var keys, i, inf, self;

	self = this;
	if (newstate) {
		this._send({
			type:	'neighbour_info',
			data:	serialize_tcl_list(['type', 'application'])
		});

		try {
			//log.debug('API setting connected to true');
			this._signals.getItem('connected').set_state(true);
			this._dispatch_event('connected', true);
		} catch (e) {
			log.error('dispatching connected event went badly: '+e);
		}
	} else {
		log.warning('server closed connection');
		try {
			//log.debug('API setting connected to false');
			this._signals.getItem('connected').set_state(false);
			keys = this._svc_signals.keys();
			for (i=0; i<keys.length; i++) {
				inf = this._svc_signals.getItem(keys[i]);
				inf.sig.set_state(false);
			}
			// TODO: nack all outstanding requests
			this._jm_prev_seq.forEach(function(seq, prev_seq) {
				var msg;

				msg = {
					type:	'jm_can',
					svc:	'sys'
				};
				self._set_default_msg_fields(msg);

				msg.seq = seq;
				msg.prev_seq = serialize_tcl_list([prev_seq]);
				self._jm_can(msg);
			});
			this._dispatch_event('connected', false);
		} catch (e2) {
			log.error('dispatching disconnected event went badly: '+e2);
		}
	}
};

//>>>
m2.api.prototype._dispatch_event = function(event, params) { //<<<
	var i;

	if (this._event_handlers.hasItem(event)) {
		var cbs = this._event_handlers.getItem(event);
		for (i=0; i<cbs.length; i++) {
			//log.debug('calling cb '+cbs[i]+',('+params+')');
			cbs[i](params);
		}
	}
};

//>>>

// vim: ft=javascript foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
