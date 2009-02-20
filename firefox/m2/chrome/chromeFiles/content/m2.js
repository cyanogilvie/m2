// vim: ft=javascript foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

function get_interface(component, interface) { //<<<
	var obj = Components.classes[component].createInstance(Components.interfaces[interface]);

	return obj;
}

//>>>
function get_service(component, interface) { //<<<
	var obj = Components.classes[component].getService(Components.interfaces[interface]);

	return obj;
}

//>>>
function m2_connect(host, port) { //<<<
	dump('attempting to connect to m2_node on ('+host+') ('+port+')\n');
	this.unique_id = 0;
	var handlers = new Hash();
	var event_handlers = new Hash();

	var pending = new Hash();
	var ack_pend = new Hash();
	var jm = new Hash();
	var jm_prev_seq = new Hash();

	var transportService = get_service(
		"@mozilla.org/network/socket-transport-service;1",
		"nsISocketTransportService");

	var transport = transportService.createTransport(null, 0, host, port, null);
	var outstream = transport.openOutputStream(0, 0, 0);
	var stream = transport.openInputStream(0, 0, 0);
	var instream = get_interface("@mozilla.org/scriptableinputstream;1",
		"nsIScriptableInputStream");
	instream.init(stream);

	// msg_handler <<<
	var msg_handler = {
		gotMsg: function(reqseq, type, payload) {
			//console.log('gotMsg: reqseq: ('+reqseq+'), type: ('+type+'), payload: ('+payload+')');
			if (handlers.hasItem(reqseq)) {
				handlers.getItem(reqseq)(type, payload);
				if (type == "ack" || type == "nack") {
					//console.log('removing handler for ('+reqseq+')');
					handlers.removeItem(reqseq);
				}
			} else {
				//console.log('no handlers found for seq: '+reqseq);
			}
		},

		closed: function(data) {
			//console.log('server closed connection');
			if (console !== undefined) {
				console.log('server closed connection');
			}
		}
	};
	// msg_handler >>>

	// api <<<
	var api = {
		_svcs: new Hash(),

		_set_default_msg_fields: function(msg) { //<<<
			if (msg.svc === undefined)		{msg.svc		= 'sys';}
			if (msg.type === undefined)		{msg.type		= 'req';}
			if (msg.seq === undefined)		{msg.seq		= '';}
			if (msg.prev_seq === undefined)	{msg.prev_seq	= '0';}
			if (msg.sell_by === undefined)	{msg.sell_by	= '';}
			if (msg.oob_type === undefined)	{msg.oob_type	= '1';}
			if (msg.oob_data === undefined)	{msg.oob_data	= '1';}
		},

		//>>>
		_receive_msg: function(msg_raw) { //<<<
			var lineend, pre_raw, pre, fmt, hdr_len, data_len, hdr, data, ofs, msg;
			//console.log('received complete message: ('+msg_raw+')');

			lineend = msg_raw.indexOf("\n");
			if (lineend == -1) {
				throw 'corrupt m2 message header: '+msg_raw;
			}
			pre_raw = msg_raw.substr(0, lineend);
			pre = parse_tcl_list(pre_raw);
			fmt = pre[0];
			if (fmt != 1) {
				throw 'Cannot parse m2 message serialization format: ('+fmt+')'
			}
			hdr_len = Number(pre[1]);
			data_len = Number(pre[2]);
			hdr = parse_tcl_list(msg_raw.substr(lineend + 1, hdr_len));
			ofs = lineend + 1 + hdr_len;
			//console.log('hdr: ',hdr);
			data = msg_raw.substr(ofs, data_len);
			//console.log('ofs: '+ofs+', data_len: '+data_len+', data: '+data);
			//console.log('msg_raw.substr('+ofs+'): ('+msg_raw.substr(ofs)+')');
			msg = {
				'svc':		hdr[0],
				'type':		hdr[1],
				'seq':		hdr[2],
				'prev_seq':	hdr[3],
				'sell_by':	hdr[4],
				'oob_type':	hdr[5],
				'oob_data':	hdr[6],
				'data':		data
			};
			this._got_msg(msg);
		},

		//>>>
		_svc_avail: function(new_svcs) { //<<<
			var i;

			for (i=0; i<new_svcs.length; i++) {
				this._svcs.setItem(new_svcs[i], true);
			}

			dispatch_event('svc_avail_changed', []);
		},

		//>>>
		_svc_revoke: function(revoked_svcs) { //<<<
			var i;

			for (i=0; i<revoked_svcs.length; i++) {
				if (this._svcs.hasItem(revoked_svcs[i])) {
					this._svcs.removeItem(revoked_svcs[i]);
				}
			}

			dispatch_event('svc_avail_changed', []);
		},

		//>>>
		_jm_can: function(msg) { //<<<
			var prev_seq_arr, i, tmp, prev_seq, cb;

			if (jm_prev_seq.hasItem(msg.seq)) {
				jm_prev_seq.removeItem(msg.seq);
			}

			prev_seq_arr = parse_tcl_list(msg.prev_seq);

			for (i=0; i<prev_seq_arr.length; i++) {
				prev_seq = prev_seq_arr[i];
				tmp = jm.getItem(prev_seq);
				tmp--;
				jm.setItem(prev_seq, tmp);
				if (pending.hasItem(prev_seq)) {
					cb = pending.getItem(prev_seq);
					if (cb !== '') {
						try {
							cb(msg, prev_seq);
						} catch(e) {
							if (console !== undefined) {
								console.log('error calling callback for jm_can: '+e);
							}
						}
					}
				}
				if (jm.getItem(prev_seq) <= 0) {
					if (pending.hasItem(prev_seq)) {
						pending.removeItem(prev_seq);
					}
					if (jm.hasItem(prev_seq)) {
						jm.removeItem(prev_seq);
					}
				}
			}
		},

		//>>>
		_response: function(msg) { //<<<
			var prev_seq_arr, i, prev_seq, cb, msgcopy;

			msgcopy = msg;
			prev_seq_arr = parse_tcl_list(msg.prev_seq);
			for (i=0; i<prev_seq_arr.length; i++) {
				prev_seq = prev_seq_arr[i];
				msgcopy.prev_seq = prev_seq;
				if (pending.hasItem(prev_seq)) {
					cb = pending.getItem(prev_seq);
					if (cb !== '') {
						try {
							cb(msgcopy);
						} catch (e) {
							if (console !== undefined) {
								console.log('error calling callback for response type: '+msg.type+': '+e);
							}
						}
					}
				}
				if (!jm.hasItem(prev_seq)) {
					continue;
				}
				if (
					jm.getItem(prev_seq) <= 0 &&
					!ack_pend.hasItem(prev_seq)
				) {
					if (pending.hasItem(prev_seq)) {
						pending.removeItem(prev_seq);
					}
					if (jm.hasItem(prev_seq)) {
						jm.removeItem(prev_seq);
					}
				}
			}
		},

		//>>>
		_got_msg: function(msg) { //<<<
			dump('got m2 msg:\n');
			dump('msg.svc: ('+msg.svc+')\n');
			dump('msg.type: ('+msg.type+')\n');
			dump('msg.seq: ('+msg.seq+')\n');
			dump('msg.prev_seq: ('+msg.prev_seq+')\n');
			dump('msg.sell_by: ('+msg.sell_by+')\n');
			dump('msg.oob_type: ('+msg.oob_type+')\n');
			dump('msg.oob_data: ('+msg.oob_data+')\n');
			dump('msg.data: ('+msg.data+')\n');
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

				case 'ack':
				case 'nack':
				case 'jm':
				case 'pr_jm':
					this._response(msg);
					break;

				default:
					break;
			}
		},

		//>>>
		_serialize_msg: function(msg) { //<<<
			var hdr, sdata;

			hdr = serialize_tcl_list([
				msg.svc,
				msg.type,
				msg.seq,
				msg.prev_seq,
				msg.sell_by,
				msg.oob_type,
				msg.oob_data
			]);
			sdata = serialize_tcl_list([
				'1',
				hdr.length,
				msg.data.length
			]);
			sdata += '\n' + hdr + msg.data;

			return sdata;
		},

		//>>>
		send: function(msg) { //<<<
			var sdata;

			this._set_default_msg_fields(msg);
			sdata = this._serialize_msg(msg);
			queue.enqueue(sdata, msg);
		}

		//>>>
	};
	// api >>>

	// queue manager <<<
	var queue = {
		_defrag_buf: new Hash,
		_msgid_seq: 0,
		_queues: new Hash,

		_receive_raw: function(packet) { //<<<
			//console.log('_queue_receive_raw: ('+packet+')');
			var lineend, head, msgid, is_tail, fragment_len, frag, rest;
			rest = packet;
			while (rest.length > 0) {
				lineend = rest.indexOf("\n");
				if (lineend == -1) {
					console.log('corrupt fragment header: '+rest);
				}
				head = parse_tcl_list(rest.substr(0, lineend));
				msgid = Number(head[0]);
				is_tail = Boolean(head[1]);
				fragment_len = Number(head[2]);
				frag = rest.substr(lineend + 1, fragment_len);
				rest = rest.substr(lineend + 1 + fragment_len);
				this._receive_fragment(msgid, is_tail, frag);
			}
		},

		//>>>
		_receive_fragment: function(msgid, is_tail, frag) { //<<<
			var complete, so_far;
			//console.log('_receive_fragment: msgid: ('+msgid+'), is_tail: ('+is_tail+'), frag: ('+frag+')');
			if (this._defrag_buf.hasItem(msgid)) {
				so_far = this._defrag_buf.getItem(msgid);
			} else {
				so_far = '';
			}
			so_far += frag;
			if (is_tail) {
				complete = so_far
				this._defrag_buf.removeItem(msgid);
				api._receive_msg(complete);
			} else {
				this._defrag_buf.setItem(msgid, so_far);
			}
		},

		//>>>
		enqueue: function(sdata, msg) { //<<<
			var msgid, payload, dgram;
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

			msgid = this._msgid_seq++;

			payload = String(msgid)+' 1 '+sdata.length+'\n'+sdata;
			dgram = String(payload.length)+'\n'+payload;
			//console.log('writing dgram: ('+dgram+')');
			outstream.write(dgram, dgram.length);
			//outstream.flush();
		}

		//>>>
	}

	// queue manager >>>

	// dataListener <<<
	var dataListener = {
		buf: "",
		onStartRequest: function(request, context) { //<<<
			console.log('onStartRequest');
			try {
				dispatch_event('connected', true);
			} catch (e) {
				console.log('dispatching connected event went badly: '+e);
			}
		}, //>>>
		onStopRequest: function(request, context, status) { //<<<
			console.log('onStopRequest, status: '+status);
			instream.close();
			outstream.close();
			msg_handler.closed();
			dispatch_event('connected', false);
		}, //>>>
		onDataAvailable: function(request, context, inputStream, offset, count) { //<<<
			//console.log('got onDataAvailable');
			var chunk = instream.read(count);
			this.buf += chunk;
			var lineend, env_header, parts, payload_size, payload;

			while (true) {
				lineend = this.buf.indexOf("\n");
				if (lineend == -1) {
					break;
				}
				env_header = this.buf.substr(0, lineend);
				parts = env_header.split(' ');
				payload_size = Number(parts[0]);
				if (isNaN(payload_size)) {
					console.log('Cannot decode packet payload length from env_header: ('+env_header+'), parts[0]: ('+parts[0]+')');
					break;
				}

				payload = this.buf.substr(lineend + 1, payload_size);
				this.buf = this.buf.substr(lineend + 1 + payload_size);
				//msg_handler.gotMsg(reqseq, type, payload);
				//console.log('got payload: ('+payload+')');
				try {
					queue._receive_raw(payload);
				} catch (e) {
					console.log('decoding inbound message went badly: '+e);
				}
			}
		} //>>>
	};
	// dataListener >>>

	var pump = get_interface("@mozilla.org/network/input-stream-pump;1",
		"nsIInputStreamPump");
	pump.init(stream, -1, -1, 0, 0, false);
	pump.asyncRead(dataListener, null);

	api.send({
		type: 'neighbour_info',
		data: serialize_tcl_list(['type', 'application'])
	});

	this.req = function(svc, data, cb) { //<<<
		var seq, msg;

		seq = this.unique_id++;

		api.send({
			svc:	svc,
			type:	'req',
			seq:	seq,
			data:	data
		});

		pending.setItem(seq, cb);
		ack_pend.setItem(seq, 1);
		jm.setItem(seq, 0);

		return seq;
	};

	//>>>
	this.rsj_req = function(jm_seq, data, cb) { //<<<
		var seq, msg;

		seq = this.unique_id++;

		api.send({
			svc:		'',
			type:		'rsj_req',
			seq:		seq,
			prev_seq:	jm_seq,
			data:		data
		});

		pending.setItem(seq, cb);
		ack_pend.setItem(seq, 1);
		jm.setItem(seq, 0);

		return seq;
	};

	//>>>
	this.jm_disconnect = function(jm_seq, prev_seq) { //<<<
		var msg;

		api.send({
			svc:		'',
			type:		'jm_disconnect',
			seq:		jm_seq,
			prev_seq:	prev_seq
		});

		if (jm_prev_seq.hasItem(jm_seq)) {
			var idx = jm_prev_seq.getItem(jm_seq).indexOf(prev_seq);
			var new_prev_seqs, old_prev_seqs, i;

			if (idx == -1) {
				// prev_seq invalid
			} else {
				jm.setItem(prev_seq, jm.getItem(prev_seq) - 1);
				if (jm.getItem(prev_seq) <= 0) {
					pending.removeItem(prev_seq);
					jm.removeItem(prev_seq);
				}
				new_prev_seqs = [];
				old_prev_seqs = jm_prev_seq.getItem(jm_seq);
				for (i=0; i<old_prev_seqs.length; i++) {
					if (old_prev_seqs[i] != prev_seq) {
						new_prev_seqs.push(old_prev_seqs[i]);
					}
				}
				if (new_prev_seqs.length > 0) {
					jm_prev_seq.setItem(jm_seq, new_prev_seqs);
				} else {
					jm_prev_seq.removeItem(jm_seq);
				}
			}
		} else {
			// Can't find jm_prev_seq(jm_seq)
		}
	};

	//>>>

	this.req_partial = function(op, data, listener) { //<<<
		var myseq = reqsequence++;
		var out = "";
		var payload = op + "\n" + data;
		handlers.setItem(myseq, listener);
		out += payload.length+' '+myseq+' req_partial'+"\n"+payload;
		//console.log('writing: ('+out+')');
		outstream.write(out,out.length);
	};

	//>>>
	this.listen_event = function(event, cb) { //<<<
		var existing;
		if (event_handlers.hasItem(event)) {
			existing = event_handlers.getItem(event);
		} else {
			existing = [];
		}
		existing.push(cb);
		event_handlers.setItem(event, existing);
	};

	//>>>
	this.dispatch_event = function(event, params) { //<<<
		if (event_handlers.hasItem(event)) {
			var cbs = event_handlers.getItem(event);
			for (i=0; i<cbs.length; i++) {
				//console.log('calling cb '+cbs[i]+',('+params+')');
				cbs[i](params);
			}
		}
	};

	//>>>

	return this;
}

//>>>
function setup_connection_status() { //<<<
	m2.listen_event('connected', function(newstate) {
		console.log('in connected handler, newstate: ('+newstate+')');
		var cx_statusNode = document.getElementById('connection_status');

		while (cx_statusNode.firstChild) {
			cx_statusNode.removeChild(cx_statusNode.firstChild);
		}

		tmpNode = document.createElement('image');
		tmpNode.setAttribute('src', 'chrome://m2/content/images/indicator_unknown.png');
		//tmpNode.setAttribute('onclick', 'm2_reconnect();');
		cx_statusNode.appendChild(tmpNode);
		tmpNode.addEventListener('click', function(evt){
			console.log('got click');
			m2_reconnect();
		}, false);

		tmpNode = document.createElement('image');
		console.log('connected_changed: ('+newstate+'), type: ('+typeof newstate+')');
		if (newstate) {
			tmpNode.setAttribute('src', 'chrome://m2/content/images/indicator_green.png');
		} else {
			tmpNode.setAttribute('src', 'chrome://m2/content/images/indicator_red.png');
		}
		cx_statusNode.appendChild(tmpNode);
	});
}

//>>>
function m2_reconnect() { //<<<
	if (typeof m2 !== undefined) {
		delete m2;
		console.log('reconnecting to m2');
	}
	m2 = m2_connect('localhost', 5300);
	setup_connection_status();
}

//>>>
