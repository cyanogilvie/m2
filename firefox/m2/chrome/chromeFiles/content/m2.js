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
function Hash() { //<<<
	this.length = 0;
	this.items = [];
	for (var i = 0; i < arguments.length; i += 2) {
		if (typeof arguments[i + 1] != 'undefined') {
			this.items[arguments[i]] = arguments[i + 1];
			this.length++;
		}
	}

	this.removeItem = function(in_key) {
		var tmp_value;
		if (typeof this.items[in_key] != 'undefined') {
			this.length--;
			tmp_value = this.items[in_key];
			delete this.items[in_key];
		}

		return tmp_value;
	};

	this.getItem = function(in_key) {
		return this.items[in_key];
	};

	this.setItem = function(in_key, in_value) {
		if (typeof in_value != 'undefined') {
			if (typeof this.items[in_key] == 'undefined') {
				this.length++;
			}

			this.items[in_key] = in_value;
		}

		return in_value;
	};

	this.hasItem = function(in_key) {
		return typeof this.items[in_key] != 'undefined';
	};
}

//>>>
function got_msg(hdr, data) { //<<<
}

//>>>
function receive(msg) { //<<<
	var lineend, pre_raw, pre, fmt, hdr_len, data_len, hdr, data, hdr_fields;
	//console.log('received complete message: ('+msg+')');

	lineend = msg.indexOf("\n");
	if (lineend == -1) {
		throw 'corrupt m2 message header: '+msg;
	}
	pre_raw = msg.substr(0, lineend);
	pre = parse_tcl_list(pre_raw);
	fmt = pre[0];
	if (fmt != 1) {
		throw 'Cannot parse m2 message serialization format: ('+fmt+')'
	}
	hdr_len = Number(pre[1]);
	data_len = Number(pre[2]);
	hdr = parse_tcl_list(msg.substr(lineend + 1, hdr_len));
	var ofs = lineend + 1 + hdr_len;
	data = msg.substr(ofs, data_len);
	hdr_fields = {
		'svc':		hdr[0],
		'type':		hdr[1],
		'seq':		hdr[2],
		'prev_seq':	hdr[3],
		'sell_by':	hdr[4],
		'oob_type':	hdr[5],
		'oob_data':	hdr[6]
	};
	console.log('got m2 message, data: ('+data+'), header: ', hdr_fields);
	got_msg(hdr_fields, data);
}

//>>>
function _receive_fragment(msgid, is_tail, frag) { //<<<
	var complete, so_far;
	//console.log('_receive_fragment: msgid: ('+msgid+'), is_tail: ('+is_tail+'), frag: ('+frag+')');
	if (_defrag_buf.hasItem(msgid)) {
		so_far = _defrag_buf.getItem(msgid);
	} else {
		so_far = '';
	}
	so_far += frag;
	if (is_tail) {
		complete = so_far
		_defrag_buf.removeItem(msgid);
		receive(complete);
	} else {
		_defrag_buf.setItem(msgid, so_far);
	}
}

//>>>
function _queue_receive_raw(msg) { //<<<
	//console.log('_queue_receive_raw: ('+msg+')');
	var lineend, head, msgid, is_tail, fragment_len, frag, rest;
	rest = msg;
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
		_receive_fragment(msgid, is_tail, frag);
	}
}

//>>>
function m2_connect(host, port) { //<<<
	console.log('attempting to connect to m2_node on ('+host+') ('+port+')');
	_defrag_buf = new Hash;
	var reqsequence = 0;
	var handlers = new Hash();
	var event_handlers = new Hash();

	/*
	var transportService =
		Components.classes["@mozilla.org/network/socket-transport-service;1"]
		.getService(Components.interfaces.nsISocketTransportService);
	*/
	var transportService = get_service(
		"@mozilla.org/network/socket-transport-service;1",
		"nsISocketTransportService");
	var transport = transportService.createTransport(null, 0, host, port, null);

	var outstream = transport.openOutputStream(0, 0, 0);

	var stream = transport.openInputStream(0, 0, 0);
	/*
	var instream =
		Components.classes["@mozilla.org/scriptableinputstream;1"]
		.createInstance(Components.interfaces.nsIScriptableInputStream);
	*/
	var instream = get_interface(
		"@mozilla.org/scriptableinputstream;1", "nsIScriptableInputStream");
	instream.init(stream);

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

	var dataListener = {
		buf: "",
		onStartRequest: function(request, context){
			console.log('onStartRequest');
			try {
				dispatch_event('connected', true);
			} catch (e) {
				console.log('dispatching connected event went badly: '+e);
			}
		},
		onStopRequest: function(request, context, status){
			console.log('onStopRequest, status: '+status);
			instream.close();
			outstream.close();
			msg_handler.closed();
			dispatch_event('connected', false);
		},
		onDataAvailable: function(request, context, inputStream, offset, count){
			//console.log('got onDataAvailable');
			var chunk = instream.read(count);
			this.buf += chunk;

			while (true) {
				var lineend = this.buf.indexOf("\n");
				if (lineend == -1) {
					break;
				}
				var env_header = this.buf.substr(0, lineend);
				var parts = env_header.split(' ');
				var payload_size = Number(parts[0]);
				if (isNaN(payload_size)) {
					console.log('Cannot decode packet payload length from env_header: ('+env_header+'), parts[0]: ('+parts[0]+')');
					break;
				}

				/*
				var reqseq = Number(parts[1]);
				if (isNaN(reqseq)) {
					console.log('Cannot decode reqseq from env_header: ('+env_header+')');
					break;
				}

				var type = parts[2];
				switch (type) {
					case 'req':
					case 'ack':
					case 'partial':
					case 'nack':
						break;

					default:
						console.log('Invalid message type: ('+type+')');
						break;
				}

				if (this.buf.length < lineend + 1 + payload_size) {
					break;
				}
				*/

				var payload = this.buf.substr(lineend + 1, payload_size);
				this.buf = this.buf.substr(lineend + 1 + payload_size);
				//msg_handler.gotMsg(reqseq, type, payload);
				//console.log('got payload: ('+payload+')');
				try {
					_queue_receive_raw(payload);
				} catch (e) {
					console.log('decoding inbound message went badly: '+e);
				}
			}
		}
	};

	/*
	var pump = Components.
		classes["@mozilla.org/network/input-stream-pump;1"].
		createInstance(Components.interfaces.nsIInputStreamPump);
	*/
	var pump = get_interface("@mozilla.org/network/input-stream-pump;1",
		"nsIInputStreamPump");
	pump.init(stream, -1, -1, 0, 0, false);
	pump.asyncRead(dataListener, null);

	this.req = function(op, data, listener) {
		var myseq = reqsequence++;
		var out = "";
		var payload = op + "\n" + data;
		handlers.setItem(myseq, listener);
		out += payload.length+' '+myseq+' req'+"\n"+payload;
		//console.log('writing: ('+out+')');
		outstream.write(out,out.length);
	};

	this.req_partial = function(op, data, listener) {
		var myseq = reqsequence++;
		var out = "";
		var payload = op + "\n" + data;
		handlers.setItem(myseq, listener);
		out += payload.length+' '+myseq+' req_partial'+"\n"+payload;
		//console.log('writing: ('+out+')');
		outstream.write(out,out.length);
	};

	this.listen_event = function(event, cb) {
		var existing;
		if (event_handlers.hasItem(event)) {
			existing = event_handlers.getItem(event);
		} else {
			existing = [];
		}
		existing.push(cb);
		event_handlers.setItem(event, existing);
	};

	this.dispatch_event = function(event, params) {
		if (event_handlers.hasItem(event)) {
			var cbs = event_handlers.getItem(event);
			for (i=0; i<cbs.length; i++) {
				console.log('calling cb '+cbs[i]+',('+params+')');
				cbs[i](params);
			}
		}
	};

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
