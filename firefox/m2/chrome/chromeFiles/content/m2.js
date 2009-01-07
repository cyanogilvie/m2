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
function m2_connect(host, port) { //<<<
	alert('attempting to connect to m2_node on ('+host+') ('+port+')');
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
			//alert('server closed connection');
			if (console !== undefined) {
				console.log('server closed connection');
			}
		}
	};

	var dataListener = {
		buf: "",
		onStartRequest: function(request, context){
			dispatch_event('connected', true);
		},
		onStopRequest: function(request, context, status){
			instream.close();
			outstream.close();
			msg_handler.closed();
			dispatch_event('connected', false);
		},
		onDataAvailable: function(request, context, inputStream, offset, count){
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
					alert('Cannot decode packet payload length from env_header: ('+env_header+')');
					break;
				}

				var reqseq = Number(parts[1]);
				if (isNaN(reqseq)) {
					alert('Cannot decode reqseq from env_header: ('+env_header+')');
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
						alert('Invalid message type: ('+type+')');
						break;
				}

				if (this.buf.length < lineend + 1 + payload_size) {
					break;
				}

				var payload = this.buf.substr(lineend + 1, payload_size);
				this.buf = this.buf.substr(lineend + 1 + payload_size);
				msg_handler.gotMsg(reqseq, type, payload);
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
	pump.asyncRead(dataListener,null);

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
				cbs[i](params);
			}
		}
	};

	return this;
}

//>>>
function setup_connection_status() { //<<<
	m2.listen_event('connected', function(newstate) {
		var cx_statusNode = document.getElementById('connection_status');

		while (cx_statusNode.firstChild) {
			cx_statusNode.removeChild(cx_statusNode.firstChild);
		}

		tmpNode = document.createElement('image');
		alert('connected_changed: ('+newstate+'), type: ('+typeof newstate+')');
		if (newstate) {
			tmpNode.setAttribute('src', 'chrome://m2/content/images/indicator_green.png');
		} else {
			tmpNode.setAttribute('src', 'chrome://m2/content/images/indicator_red.png');
		}
		cx_statusNode.appendChild(tmpNode);
	});
}

//>>>
