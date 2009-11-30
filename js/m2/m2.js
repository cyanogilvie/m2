function m2() {} // namespace

m2.api = function(params) { //<<<
	if (typeof params == 'undefined') {
		console.log('lame');
		return;
	}
	// Public
	this.host = 'localhost';
	this.port = 5301;

	if (typeof window != 'undefined' && typeof window.console != 'undefined') {
		this.log = console.log;
	} else {
		if (typeof print != 'undefined') {
			this.log = function(msg) {
				print(msg);
			};
		} else if (typeof dump != 'undefined') {
			this.log = function(msg) {
				dump(msg+'\n');
			};
		} else {
			this.log = function(msg) {};
		}
	}

	console.log('Constructing m2.api: ', params);

	if (typeof params != 'undefined') {
		if (typeof params.host != 'undefined') {
			this.host = params.host;
		}
		if (typeof params.port != 'undefined') {
			this.port = params.port;
		}
		if (typeof params.log != 'undefined') {
			this.log = params.log;
		}
	}

	// Private
	var self;
	self = this;
	this._unique_id = 0;
	this._handlers = new Hash;
	this._event_handlers = new Hash;
	this._pending = new Hash;
	this._ack_pend = new Hash;
	this._jm = new Hash;
	this._jm_prev_seq = new Hash;
	this._socket = null;
	this._signals = new Hash;
	this._svcs = new Hash;
	this._svc_signals = new Hash;
	this._defrag_buf = new Hash;
	this._msgid_seq = 0;
	this._queues = new Hash;

	this.log('attempting to connect to m2_node on ('+this.host+') ('+this.port+')');
	this._signals.setItem('connected', new Signal({
		name: 'connected'
	}));

	this._socket = new jsSocket({
		keepalive: null,
		logger: this.log,
		debug: false
	});
	console.log('====== API constructed new jsSocket: ', this._socket);

	this._socket.onData = function(data) {
		self._receive_raw(data);
	};
	//this._socket.onData = this._receive_raw;
	this._socket.onStatus = function(type, val) {
		self._socket_onStatus(type, val);
	}
	//this._socket.onStatus = this._socket_onStatus;

	this._socket.onLoaded = function(data) {
		self.log('====== API socket loaded, attempting to connect to '+self.host+':'+self.port);
		self._socket.open(self.host, self.port);
	};
};

//>>>
m2.api.prototype.destroy = function() { //<<<
	// TODO: close socket
	return null;
};

//>>>

// Public
m2.api.prototype.signal_ref = function(name) { //<<<
	if (!this._signals.hasItem(name)) {
		throw('Signal "'+name+'" does\'t exist');
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
m2.api.prototype.req = function(svc, data, cb) { //<<<
	var seq;

	seq = this._unique_id++;

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
	var seq;

	seq = this._unique_id++;

	this._send({
		svc:		'',
		type:		'rsj_req',
		seq:		seq,
		prev_seq:	jm_seq,
		data:		data
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
		var idx = this._jm_prev_seq.getItem(jm_seq).indexOf(prev_seq);
		var new_prev_seqs, old_prev_seqs, i;

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
	if (msg.meta === undefined)		{msg.meta		= {};}
	if (msg.oob_type === undefined)	{msg.oob_type	= '1';}
	if (msg.oob_data === undefined)	{msg.oob_data	= '1';}
};

//>>>
m2.api.prototype._receive_msg = function(msg_raw) { //<<<
	var lineend, pre_raw, pre, fmt, hdr_len, data_len, hdr, data, ofs, msg;
	this.log('received complete message: ('+msg_raw+')');

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
	var i;
	for (i=0; i<hdr.length; i++) {
		this.log('hdr: '+i+' = ('+hdr[i]+')');
	}
	data = msg_raw.substr(ofs, data_len);
	this.log('ofs: '+ofs+', data_len: '+data_len+', data: '+data);
	this.log('msg_raw.substr('+ofs+'): ('+msg_raw.substr(ofs)+')');
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
	var prev_seq_arr, i, tmp, prev_seq, cb, e;

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
					this.log('error calling callback for jm_can: '+e);
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
	//this.log('_response: ', msg);
	var prev_seq_arr, i, prev_seq, cb, msgcopy, e;

	msgcopy = msg;
	prev_seq_arr = parse_tcl_list(msg.prev_seq);
	for (i=0; i<prev_seq_arr.length; i++) {
		prev_seq = prev_seq_arr[i];
		msgcopy.prev_seq = prev_seq;
		if (this._pending.hasItem(prev_seq)) {
			cb = this._pending.getItem(prev_seq);
			if (cb !== '') {
				try {
					//this.log('Calling callback with: ', msgcopy);
					cb(msgcopy);
				} catch (e) {
					this.log('error calling callback for response type: '+msg.type+': '+e);
				}
			} else {
				this.log('No callback registered for prev_seq: '+prev_seq);
			}
		} else {
			this.log('No _pending entry for prev_seq: '+prev_seq);
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
m2.api.prototype._got_msg = function(msg) { //<<<
	this.log('got m2 msg:');
	this.log('msg.svc: ('+msg.svc+')');
	this.log('msg.type: ('+msg.type+')');
	this.log('msg.seq: ('+msg.seq+')');
	this.log('msg.prev_seq: ('+msg.prev_seq+')');
	this.log('msg.meta: ('+msg.meta+')');
	this.log('msg.oob_type: ('+msg.oob_type+')');
	this.log('msg.oob_data: ('+msg.oob_data+')');
	this.log('msg.data: ('+msg.data+')');
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

		case 'pr_jm':
			this._jm.setItem(msg.prev_seq, this._jm.getItem(msg.prev_seq) + 1);
		case 'ack':
		case 'nack':
		case 'jm':
			this._response(msg);
			break;

		default:
			this.log('Invalid msg.type: ('+msg.type+')');
			var key;
			for (key in msg) {
				this.log('msg.'+key+': ('+msg[key]+')');
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

	console.log('Got request to send msg: ', msg);
	this._set_default_msg_fields(msg);
	sdata = this._serialize_msg(msg);
	this.log('Serialized '+sdata.length+' bytes of data to send');
	this._enqueue(sdata, msg);
};

//>>>
m2.api.prototype._receive_fragment = function(msgid, is_tail, frag) { //<<<
	var complete, so_far;
	this.log('_receive_fragment: msgid: ('+msgid+'), is_tail: ('+is_tail+'), frag: ('+frag+')');
	if (this._defrag_buf.hasItem(msgid)) {
		so_far = this._defrag_buf.getItem(msgid);
	} else {
		so_far = '';
	}
	so_far += frag;
	if (is_tail) {
		complete = so_far;
		this._defrag_buf.removeItem(msgid);
		this._receive_msg(complete);
	} else {
		this._defrag_buf.setItem(msgid, so_far);
	}
};

//>>>
m2.api.prototype._receive_raw = function(packet_base64) { //<<<
	var packet;
	packet = Utf8.decode(Base64.decode(packet_base64));
	this.log('_queue_receive_raw: ('+packet+')');
	var lineend, head, msgid, is_tail, fragment_len, frag, rest;
	rest = packet;
	while (rest.length > 0) {
		lineend = rest.indexOf("\n");
		if (lineend == -1) {
			this.log('corrupt fragment header: '+rest);
		}
		head = parse_tcl_list(rest.substr(0, lineend));
		msgid = Number(head[0]);
		is_tail = Boolean(head[1]);
		fragment_len = Number(head[2]);
		frag = rest.substr(lineend + 1, fragment_len);
		rest = rest.substr(lineend + 1 + fragment_len);
		this._receive_fragment(msgid, is_tail, frag);
	}
};

//>>>
m2.api.prototype._enqueue = function(sdata, msg) { //<<<
	var msgid, payload, udata;
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
	this.log('sending msg:');
	this.log('msg.svc: ('+msg.svc+')');
	this.log('msg.type: ('+msg.type+')');
	this.log('msg.seq: ('+msg.seq+')');
	this.log('msg.prev_seq: ('+msg.prev_seq+')');
	this.log('msg.meta: ('+msg.meta+')');
	this.log('msg.oob_type: ('+msg.oob_type+')');
	this.log('msg.oob_data: ('+msg.oob_data+')');
	this.log('msg.data: ('+msg.data+')');
	*/

	msgid = this._msgid_seq++;

	//udata = Utf8.encode(sdata);

	//payload = Base64.encode(String(msgid)+' 1 '+udata.length+'\n'+udata);
	payload = Base64.encode(String(msgid)+' 1 '+sdata.length+'\n'+sdata);
	//payload = Base64.encode(Utf8.encode(String(msgid)+'\n'+sdata));
	this._socket.send(payload);
};

//>>>
m2.api.prototype._socket_onStatus = function(type, val) { //<<<
	var e, keys, i, inf;
	switch (type) {
		case 'connecting':
			break;

		case 'connected':
			this._send({
				type: 'neighbour_info',
				data: serialize_tcl_list(['type', 'application'])
			});

			try {
				this.log('API setting connected to true');
				this._signals.getItem('connected').set_state(true);
				this._dispatch_event('connected', true);
			} catch (e) {
				this.log('dispatching connected event went badly: '+e);
			}
			break;

		case 'disconnected':
			this.log('server closed connection');
			try {
				keys = this._svc_signals.keys();
				for (i=0; i<keys.length; i++) {
					inf = this._svc_signals.getItem(keys[i]);
					inf.sig.set_state(false);
				}
				this.log('API setting connected to false');
				this._signals.getItem('connected').set_state(false);
				this._dispatch_event('connected', false);
			} catch (e) {
				this.log('dispatching disconnected event went badly: '+e);
			}
			break;

		case 'waiting':
			break;

		case 'failed':
			break;

		default:
			this.log('Unhandled socket status: "'+type+'"');
			break;
	}
};

//>>>
m2.api.prototype._dispatch_event = function(event, params) { //<<<
	var i;

	if (this._event_handlers.hasItem(event)) {
		var cbs = this._event_handlers.getItem(event);
		for (i=0; i<cbs.length; i++) {
			//this.log('calling cb '+cbs[i]+',('+params+')');
			cbs[i](params);
		}
	}
};

//>>>

// vim: ft=javascript foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
