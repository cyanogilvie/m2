m2.connector = function(a_auth, a_svc, params) { //<<<<
	if (typeof params == 'undefined') {
		params = {};
	}
	Baselog.call(this, params);

	this.auth = a_auth;
	this.svc = a_svc;

	this._pbkey = null;
	this._e_chan = null;
	this._e_chan_prev_seq = null;
	this._skey = null;
	this._cookie = null;

	var self = this;
	this.signals = {};
	this.signals.available = this.auth.svc_signal(this.svc);
	this.signals.connected = new Signal({name: this.svc+' connected'});
	this.signals.authenticated = new Signal({name: this.svc+' authenticated'});
	this.signals.got_svc_pbkey = new Signal({name: this.svc+' got_svc_pbkey'});
	this.signals.connect_ready = new Gate({name: this.svc+' connect_ready', mode: 'and'});
	this.dominos = {};
	this.dominos.need_reconnect = new Domino({name: this.svc+' reconnect'});

	this.signals.connect_ready.attach_input(this.auth.signal_ref('authenticated'));
	this.signals.connect_ready.attach_input(this.signals.got_svc_pbkey);
	this.signals.connect_ready.attach_input(this.signals.available);

	this.auth.signal_ref('authenticated').attach_output(function(newstate) {
		self._authenticated_changed(newstate);
	});
	this.dominos.need_reconnect.attach_output(function(){
		self._reconnect();
	});
	this.signals.connect_ready.attach_output(function(newstate){
		self._connect_ready_changed(newstate);
	});
};

//>>>>
m2.connector.prototype = new Baselog();
m2.connector.prototype.constructor = m2.connector;

m2.connector.prototype.destroy = function() { //<<<<
	// TODO: the stuff that goes here
	return null;
};

//>>>>

m2.connector.prototype.signal_ref = function(name) { //<<<<
	if (typeof this.signals[name] == 'undefined') {
		throw('Signal "'+name+'" doesn\'t exist');
	}
	return this.signals[name];
};

//>>>>
m2.connector.prototype.req_async = function(op, data, cb) { //<<<<
	if (!this.signals.authenticated.state()) {
		throw('Cannot issue request - not authenticated yet');
	}
	return this.auth.rsj_req(this._e_chan, serialize_tcl_list([op, data]), cb);
};

//>>>>
m2.connector.prototype.chan_req_async = function(jmid, data, cb) { //<<<<
	if (!this.signals.authenticated.state()) {
		throw('Cannot issue request - not authenticated yet');
	}
	return this.auth.rsj_req(jmid, data, cb);
};

//>>>>
m2.connector.prototype.jm_disconnect = function(seq, prev_seq) { //<<<<
	return this.auth.jm_disconnect(seq, prev_seq);
};

//>>>>
m2.connector.prototype.disconnect = function() { //<<<<
	if (this.signals.connected.state()) {
		this.signals.authenticated.set_state(false);
		this.signals.connected.set_state(false);
		if (this._e_chan !== null) {
			this.jm_disconnect(this._e_chan, this._e_chan_prev_seq);
			this._e_chan = null;
			this._e_chan_prev_seq = null;
		}
	}
};

//>>>>
m2.connector.prototype.unique_id = function() { //<<<<
	return this.auth.unique_id();
};

//>>>>
m2.connector.prototype.auth = function() { //<<<<
	return this.auth;
};

//>>>>
m2.connector.prototype._connect_ready_changed = function(newstate) { //<<<<
	if (newstate) {
		//this.log('debug', 'setting reconnect in motion');
		this.dominos.need_reconnect.tip();
	}
};

//>>>>
m2.connector.prototype._reconnect = function() { //<<<<
	var csprng, skey, cookie, n, e, msg, ks, iv, tail, self;

	this.log('debug', 'reconnecting to '+this.svc);
	if (this.signals.connected.state()) {
		this.disconnect();
	}

	csprng = new cfcrypto.csprng();

	skey = this.auth.generate_key();
	cookie = csprng.getbytes(8);
	//console.log('this._pbkey: ', this._pbkey);
	n = this._pbkey.n;
	e = this._pbkey.e;
	//this.log('debug', 'n bitlength: '+n.bitLength());
	//this.log('debug', 'Encrypting session key with n: '+n.toString(16)+', e: '+e.toString(16));
	msg = cfcrypto.rsa.RSAES_OAEP_Encrypt(n, e, skey, "");
	//this.log('debug', 'skey base64: '+Base64.encode(skey));
	//this.log('debug', 'reconnect msg length: '+msg.length+' base64 e_skey: '+Base64.encode(msg));
	ks = new cfcrypto.blowfish(skey);
	iv = csprng.getbytes(8);
	tail = ks.encrypt_cbc(serialize_tcl_list([cookie, this.auth.fqun(), iv]), iv);
	this._skey = skey;
	this._cookie = cookie;

	self = this;
	//this.log('debug', '"setup " cookie base64: '+Base64.encode(cookie));
	this.auth.req(this.svc, 'setup '+serialize_tcl_list([msg, tail, iv]), function(msg){
		self._resp(msg);
	});
};

//>>>>
m2.connector.prototype._resp = function(msg) { //<<<<
	var svc_cookie, self, pdata;

	self = this;

	switch (msg.type) {
		case 'ack': //<<<<
			if (this._e_chan === null) {
				this.log('error', 'Incomplete encrypted channel setup: got ack but no pr_jm');
				return;
			}
			this.signals.connected.set_state(true);
			//this.log('debug', 'msg.data.length: '+msg.data.length+' msg.data: (e_cookie2 base64) '+Base64.encode(msg.data));
			svc_cookie = this.auth.decrypt_with_session_prkey(msg.data);
			//this.log('debug', 'Got cookie2: base64: '+Base64.encode(svc_cookie));
			//this.log('debug', 'sending proof of identity');
			this.auth.rsj_req(this._e_chan, svc_cookie, function(msg){
				self._auth_resp(msg);
			});
			break; //>>>>

		case 'nack': //<<<<
			if (this._e_chan !== null) {
				this._e_chan = null;
			}
			if (this._e_chan_prev_seq !== null) {
				this._e_chan_prev_seq = null;
			}
			this.log('error', 'Got nacked: ('+msg.data+')');
			break; //>>>>

		case 'pr_jm': //<<<<
			if (this._e_chan === null) {
				pdata = this.auth.decrypt(this._skey, msg.data);
				if (pdata === this._cookie) {
					this._e_chan = msg.seq;
					this._e_chan_prev_seq = msg.prev_seq;
					//this.log('debug', 'got matching cookie, storing e_chan ('+this._e_chan+') and registering it with auth::register_jm_key');
					this.auth.register_jm_key(this._e_chan, this._skey);
				} else {
					//this.log('error', 'did not get correct response from component: expecting: ('+Base64.encode(this._cookie)+')['+this._cookie.length+'] got: ('+Base64.encode(pdata)+')['+pdata.length+']');
					this.log('error', 'did not get correct response from component');
				}
			}
			break; //>>>>

		case 'jm_can': //<<<<
			if (this._e_chan !== null && this._e_chan == msg.seq) {
				this.signals.connected.set_state(false);
				this.signals.authenticated.set_state(false);
				this._e_chan = null;
				this._e_chan_prev_seq = null;
			}
			break; //>>>>

		default: //<<<<
			this.log('warning', 'Not expecting response type ('+msg.type+')');
			break; //>>>>
	}
};

//>>>>
m2.connector.prototype._auth_resp = function(msg) { //<<<<
	switch (msg.type) {
		case 'ack':
			//this.log('debug', 'got ack: ('+msg.data+')');
			this.signals.authenticated.set_state(true);
			break;

		case 'nack':
			this.log('error', 'got nack: ('+msg.data+')');
			break;

		default:
			this.log('error', 'unexpected type: ('+msg.type+')');
			break;
	}
};

//>>>>
m2.connector.prototype._authenticated_changed = function(newstate) { //<<<<
	var self;

	if (newstate) {
		//this.log('debug', 'requesting public key for ('+this.svc+') ...');
		self = this;
		this.auth.get_svc_pbkey(this.svc, function(ok, data) {
			if (ok) {
				self._pbkey_asc = data;
				//self.log('debug', 'got public key ascii format for ('+self.svc+'), loading into key ...');
				try {
					//self.log('debug', 'Attempting to extract public key from: '+self._pbkey_asc);
					self._pbkey = cfcrypto.rsa.load_asn1_pubkey_from_value(self._pbkey_asc);
					//self.log('debug', 'got public key for ('+self.svc+')');
					//console.log('self._pbkey: ', self._pbkey);
					self.signals.got_svc_pbkey.set_state(true);
				} catch(e) {
					self.log('error', 'error decoding public key for ('+self.svc+'): '+e);
				}
			} else {
				self.log('error', 'error fetching public key for ('+self.svc+'): '+data);
			}
		});
	} else {
		this.signals.got_svc_pbkey.set_state(false);
		if (this._pbkey !== null) {
			this._pbkey = null;
		}
	}
};

//>>>>

// vim: ft=javascript foldmethod=marker foldmarker=<<<<,>>>> ts=4 shiftwidth=4
