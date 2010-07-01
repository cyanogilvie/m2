/*
 * TODO
 * session_pbkey keypair generation
 * upgrade jsSocket to new version that doesn't have jQuery dependency
 */


m2.authenticator = function(params) { //<<<
	//log.debug('Constructing m2.authenticator: ', params);
	m2.api.call(this, params);
	//log.debug('this is ', this);

	// Public
	this.pbkey = 'authenticator.pub';
	this.profile_cb = null;
	this.default_domain = null;

	if (typeof params != 'undefined') {
		if (typeof params.host != 'undefined') {
			this.host = params.host;
		}
		if (typeof params.port != 'undefined') {
			this.port = params.port;
		}

		if (typeof params.pbkey != 'undefined') {
			this.pbkey = params.pbkey;
		}
		if (typeof params.profile_cb != 'undefined') {
			this.profile_cb = params.profile_cb;
		}
		if (typeof params.default_domain != 'undefined') {
			this.default_domain = params.default_domain;
		}
	}

	// Private
	var self;
	self = this;
	//this._signals = new Hash(); // Done by m2 constructor
	this._signals.setItem('available', this.svc_signal('authenticator'));
	this._signals.setItem('established', new Signal({name: 'established'}));
	this._signals.setItem('authenticated', new Signal({name: 'authenticated'}));
	this._signals.setItem('login_pending', new Gate({name: 'login_pending', mode: 'and'}));
	this._signals.setItem('login_allowed', new Gate({name: 'login_allowed', mode: 'and'}));
	this._signals.setItem('got_perms', new Signal({name: 'got_perms'}));
	this._signals.setItem('got_attribs', new Signal({name: 'got_attribs'}));
	this._signals.setItem('got_prefs', new Signal({name: 'got_prefs'}));

	this._signals.getItem('login_allowed').attach_input(
		this._signals.getItem('login_pending'), 'inverted');
	this._signals.getItem('login_allowed').attach_input(
		this._signals.getItem('authenticated'), 'inverted');
	this._signals.getItem('login_allowed').attach_input(
		this._signals.getItem('established'));

	this._signals.getItem('connected').attach_output(function(newstate) {
		if (!newstate) {
			// Reset login_pending if our connection is dropped while a login
			// request was in flight
			self._signals.getItem('login_pending').set_state(false);
		}
	});

	// Set this to something that initiates a profile selection process
	// with the user, and calls this.select_profile(seq, profilename) when done.
	// Callback is passed the arguments (seq, profiles_available_dict)
	this.profile_cb = null;
	this.connected_users_changed = null;

	//this._pubkey = cfcrypto.rsa.load_asn1_pubkey_from_value(this.pbkey);
	this._pubkey = this._load_pbkey(this.pbkey);
	this._keys = {};
	this._keys.main = this.generate_key();
	this.enc_chan = null;
	this.login_chan = null;
	this._fqun = null;
	this.session_prkey = null;
	this.login_subchans = new Hash();
	this.perms = new Hash();
	this.attribs = new Hash();
	this.prefs = new Hash();
	this.admin_info = {};
	this.session_pbkey_chan = null;
	this.last_login_message = '';

	this._signals.getItem('connected').attach_output(function(newstate) {
		if (!newstate) {
			self._signals.getItem('available').set_state(false);
		}
	});
	this._signals.getItem('available').attach_output(function(newstate) {
		if (newstate) {
			self._crypt_setup();
		} else {
			self._signals.getItem('established').set_state(false);
		}
	});
};

//>>>
m2.authenticator.prototype = new m2.api();
m2.authenticator.prototype.constructor = m2.authenticator;

m2.authenticator.prototype.destroy = function() { //<<<
	// TODO: all the things that must happen here ;)
	return m2.api.destroy.call(this);
};

//>>>

m2.authenticator.prototype._load_pbkey = function(pbkey) { //<<<
	var K, l;

	l = list2dict(pbkey);

	if (typeof l.n == 'undefined' || typeof l.e == 'undefined') {
		throw('Not a public key: '+pbkey);
	}

	K = {};
	K.n = new BigInteger(l.n, '10');
	K.e = new BigInteger(l.e, '10');

	return K;
};

//>>>
m2.authenticator.prototype.login = function(username, password) { //<<<
	var self;

	if (!this._signals.getItem('login_allowed').state()) {
		throw('Cannot login at this time');
	}

	if (username.indexOf('@') == -1) {
		if (this.default_domain === null) {
			throw('No domain specified and no default domain');
		}
		username += '@'+this.default_domain;
	}

	this._signals.getItem('login_pending').set_state(true);

	self = this;
	this.rsj_req(this.enc_chan, serialize_tcl_list(['login', username, password]), function(msg) {
		var before, after, K, pbkey, key, parts, op;

		switch (msg.type) {
			case 'ack': //<<<
				if (self.login_chan === null) {
					log.warning('got ack, but no login_chan!');
				}

				self._fqun = username;
				log.debug('Logged in ok, generating key');
				before = new Date();
				K = cfcrypto.rsa.RSAKG(512, 0x10001);
				after = new Date();
				log.debug('512 bit key generation time: '+(after-before)+'ms');
				pbkey = [
					'n', K.n,
					'e', K.e
				];
				//log.debug('session_prkey: ', K);
				//log.debug('n: '+K.n.toString(10)+', e: '+K.e.toString(10));
				self.session_prkey = K;
				self.rsj_req(self.login_chan[0], serialize_tcl_list(['session_pbkey_update', serialize_tcl_list(pbkey)]), function(msg) {
					switch (msg.type) {
						case 'ack': //<<<
							self._signals.getItem('authenticated').set_state(true);
							self._signals.getItem('login_pending').set_state(false);
							break; //>>>

						case 'nack': //<<<
							self._signals.getItem('login_pending').set_state(false);
							break; //>>>

						case 'pr_jm': //<<<
							if (self.session_pbkey_chan !== null) {
								log.warn('Already have session_pbkey_chan: ('+self.session_pbkey_chan+')');
							}
							self.session_pbkey_chan = [msg.seq, msg.prev_seq];
							break; //>>>

						case 'jm': //<<<
							if (self.session_pbkey_chan === null || msg.seq != self.session_pbkey_chan[0]) {
								log.warn('unrecognised jm chan: ('+msg.seq+')');
								return;
							}

							parts = parse_tcl_list(msg.data);
							op = parts[0];
							switch (op) {
								case 'refresh_key':
									log.debug('jm(session_pbkey_chan): got notifiction to renew session keypair');
									log.debug('jm(session_pbkey_chan): generating keypair');
									before = new Date();
									K = cfcrypto.rsa.RSAKG(512, 0x10001, 16);
									after = new Date();
									log.debug('512 bit key generation time: '+(after-before)+'ms');
									pbkey = [
										'n', K.n,
										'e', K.e
									];
									self.session_prkey = K;
									log.debug('jm(session_pbkey_chan): sending public key to backend');

									self.rsj_req(self.session_pbkey_chan[0], serialize_tcl_list(['session_pbkey_update', pbkey]), function(msg) {
										switch (msg.type) {
											case 'ack':
												log.debug('session key update ok: ('+msg.data+')');
												break;

											case 'nack':
												log.error('session key update problem: ('+msg.data+')');
												break;

											default:
												log.error('unhandled response type: ('+msg.type+') to session_pbkey_update request');
												break;
										}
									});
									break;

								default:
									break;
							}
							break; //>>>

						case 'jm_can': //<<<
							if (self.session_pbkey_chan !== null && self.session_pbkey_chan[0] == msg.seq) {
								self.session_pbkey_chan = null;
								self.logout();
							} else {
								log.error('error: non session_pbkey_chan jm cancelled');
							}
							break; //>>>

						default: //<<<
							log.error('Unexpected response type to session_pbkey_update request: ('+msg.type+')');
							break; //>>>
					}
				});
				break; //>>>

			case 'nack': //<<<
				self.last_login_message = msg.data;
				log.error('Error logging in: '+msg.data);
				self._signals.getItem('login_pending').set_state(false);
				break; //>>>

			case 'pr_jm': //<<<
				self._login_resp_pr_jm(msg);
				break; //>>>

			case 'jm': //<<<
				key = msg.seq + '/' + msg.prev_seq;
				if (!self.login_subchans.hasItem(key)) {
					log.warning('not sure what to do with jm: ('+msg.svc+','+msg.seq+','+msg.prev_seq+') ('+msg.data+')');
					return;
				}

				switch (self.login_subchans.getItem(key)) {
					case 'userinfo':
						self._update_userinfo(parse_tcl_list(msg.data));
						break;

					case 'admin_chan':
						self._admin_chan_update(parse_tcl_list(msg.data));
						break;

					default:
						log.warning('registered but unhandled login subchan seq: ('+key+') type: ('+self.login_subchans.getItem(key)+')');
						break;
				}
				break; //>>>

			case 'jm_can': //<<<
				if (self.login_chan !== null && self.login_chan[0] == msg.seq) {
					self.login_chan = null;
					log.debug('Got login_chan cancel, calling logout');
					self.logout();
				} else {
					key = msg.seq + '/' + msg.prev_seq;
					if (self.login_subchans.hasItem(key)) {
						switch (self.login_subchans.getItem(key)) {
							case 'userinfo':
								log.debug('userinfo channel cancelled');
								self._signals.getItem('got_perms').set_state(false);
								self._signals.getItem('got_attribs').set_state(false);
								self._signals.getItem('got_prefs').set_state(false);

								self.perms = new Hash();
								self.attribs = new Hash();
								self.prefs = new Hash();
								break;

							case 'admin_chan':
								log.debug('admin_chan cancelled');
								self.admin_info = {};
								break;

							case 'session_chan':
								log.debug('session_chan cancelled');
								break;

							default:
								log.warning('registered but unhandled login subchan cancel: seq: ('+msg.seq+') type: ('+self.login_subchans.getItem(key)+')');
								break;
						}
						self.login_subchans.removeItem(key);
					} else {
						log.warning('unexpected jm_can: seq: ('+msg.seq+')');
					}
				}
				break; //>>>

			default: //<<<
				log.warning('Unexpected response type to login request: '+msg.type);
				break; //>>>
		}
	});
};

//>>>
m2.authenticator.prototype.logout = function() { //<<<
	var self;

	log.debug('In logout');
	if (!this._signals.getItem('authenticated').state()) {
		log.warning('Authenticator logout: not logged in');
		return;
	}
	if (this.login_chan !== null) {
		log.debug('Sending login_chan jm_disconnect: seq: '+this.login_chan[0]+', prev_seq: '+this.login_chan[1]);
		this.jm_disconnect(this.login_chan[0], this.login_chan[1]);
		this.login_chan = null;
	}
	self = this;
	this.login_subchans.forEach(function(key, value) {
		var parts;
		parts = key.split('/');
		log.debug('Sending login subchan disconnect: seq: '+parts[0]+', prev_seq: '+parts[1]);
		self.jm_disconnect(parts[0], parts[1]);
		switch (value) {
			case 'userinfo':
				self._signals.getItem('got_perms').set_state(false);
				self._signals.getItem('got_attribs').set_state(false);
				self._signals.getItem('got_prefs').set_state(false);

				self.perms = new Hash();
				self.attribs = new Hash();
				self.prefs = new Hash();
				break;

			case 'admin_chan':
				self.admin_info = {};
				break;

			case 'session_chan':
				break;

			default:
				log.warning('Cancelled unhandled login subchan type "'+value+'"');
				break;
		}
	});
	this.login_subchans = new Hash();
	if (this.session_pbkey_chan !== null) {
		log.debug('Sending session_pbkey_chan jm_disconnect: seq: '+this.session_pbkey_chan[0]+', prev_seq: '+this.session_pbkey_chan[1]);
		this.jm_disconnect(this.session_pbkey_chan[0], this.session_pbkey_chan[1]);
		this.session_pbkey_chan = null;
	}
	this._signals.getItem('authenticated').set_state(false);
};

//>>>
m2.authenticator.prototype.get_svc_pbkey = function(svc, cb) { //<<<
	var self;

	if (!this._signals.getItem('authenticated').state()) {
		throw('Not authenticated yet');
	}

	this.rsj_req(this.login_chan[0], serialize_tcl_list(['get_svc_pubkey', svc]), function(msg) {
		switch (msg.type) {
			case 'ack':
				cb(true, msg.data);
				break;

			case 'nack':
				cb(false, msg.data);
				break;

			default:
				log.warning('Unexpected response type to get_svc_pubkey request: ('+msg.type+')');
				break;
		}
	});
};

//>>>
m2.authenticator.prototype.connect_svc = function(svc) { //<<<
	return new m2.connector(this, svc);
};

//>>>
m2.authenticator.prototype.decrypt_with_session_prkey = function(data) { //<<<
	return cfcrypto.rsa.RSAES_OAEP_Decrypt(this.session_prkey, data, '');
};

//>>>
m2.authenticator.prototype.fqun = function() { //<<<
	if (!this._signals.getItem('authenticated').state()) {
		throw('Not authenticated yet');
	}
	return this._fqun;
};

//>>>
m2.authenticator.prototype.get_user_pbkey = function(fqun, cb) { //<<<
	// Don't think this is needed on the client side.  I don't envision
	// implementing components in javascript
	var self;

	if (!this._signals.getItem('established').state()) {
		throw('No encrypted channel to the authenticator established yet');
	}
	//log.debug('sending request on '+this.enc_chan);
	self = this;
	this.rsj_req(this.enc_chan, serialize_tcl_list(['get_user_pbkey', fqun]), function(msg) {
		switch (msg.type) {
			case 'ack':
				cb(true, msg.data);
				break;

			case 'nack':
				cb(false, msg.data);
				break;

			default:
				break;
		}
	});
};

//>>>
m2.authenticator.prototype.last_login_message = function() { //<<<
	return this.last_login_message;
};

//>>>
m2.authenticator.prototype.auth_chan_req = function(data, cb) { //<<<
	if (this._signals.getItem('authenticated').state()) {
		throw('Not authenticated yet');
	}

	this.rsj_req(this.login_chan[0], data, cb);
};

//>>>
m2.authenticator.prototype.enc_chan_req = function(data, cb) { //<<<
	// Unneeded in client side api
	throw('enc_chan_req not supported in javascript implementation');
};

//>>>
m2.authenticator.prototype.perm = function(perm) { //<<<
	if (!this._signals.getItem('got_perms').state()) {
		throw('Haven\'t received perms yet');
	}
	return this.perms.hashItem(perm);
};

//>>>
m2.authenticator.prototype.attrib = function(attrib, default_value) { //<<<
	if (!this._signals.getItem('got_attribs').state()) {
		throw('Haven\'t received attribs yet');
	}
	if (this.attribs.hasItem(attrib)) {
		return this.attribs.getItem(attrib);
	} else {
		if (typeof default_value != 'undefined') {
			log.debug('attrib not set, using fallback');
			return default_value;
		} else {
			throw('No attrib ('+attrib+') defined');
		}
	}
};

//>>>
m2.authenticator.prototype.pref = function(pref, default_value) { //<<<
	if (!this._signals.getItem('got_prefs').state()) {
		throw('Haven\'t received prefs yet');
	}
	if (this.prefs.hasItem(pref)) {
		return this.prefs.getItem(pref);
	} else {
		if (typeof default_value != 'undefined') {
			return default_value;
		} else {
			throw('No pref ('+pref+') defined');
		}
	}
};

//>>>
m2.authenticator.prototype.set_pref = function(pref, newvalue) { //<<<
	var self;

	if (!this._signals.getItem('authenticated').state()) {
		throw('Not authenticated yet');
	}
	self = this;
	this.rsj_req(this.login_chan[0], serialize_tcl_list(['set_pref', pref, newvalue]), function(msg) {
		switch (msg.type) {
			case 'ack':
				log.debug('pref updated');
				break;

			case 'nack':
				log.error('error setting pref ('+pref+') to newvalue: ('+newvalue+'): '+msg.data);
				break;

			default:
				log.warning('Unexpected response type ('+msg.type+') to set_pref request');
				break;
		}
	});
};

//>>>
m2.authenticator.prototype.change_password = function(old, new1, new2) { //<<<
	var self;

	if (!this._signals.getItem('authenticated').state()) {
		throw('Not authenticated yet');
	}

	self = this;
	this.rsj_req(this.login_chan[0], serialize_tcl_list(['change_password', old, new1, new2]), function(msg) {
		switch (msg.type) {
			case 'ack':
				log.debug('password updated');
				break;

			case 'nack':
				log.error('error updating password: '+msg.data);
				break;

			default:
				log.warning('Unexpected response type ('+msg.type+') to change_password request');
				break;
		}
	});
};

//>>>
m2.authenticator.prototype.is_admin = function() { //<<<
	if (!this._signals.getItem('authenticated').state()) {
		throw('Not authenticated yet');
	}
	return this.perm('system.admin');
};

//>>>
m2.authenticator.prototype.get_admin_info = function() { //<<<
	return this.admin_info;
};

//>>>
m2.authenticator.prototype.admin = function(op, data, cb) { //<<<
	var self;

	if (!this.is_admin()) {throw('Not an administrator');}

	self = this;
	this.rsj_req(this.admin_info.admin_chan[0], serialize_tcl_list([op, data]), function(msg) {
		switch (msg.type) {
			case 'ack':
				cb(true, msg.data);
				break;

			case 'nack':
				cb(false, msg.data);
				break;

			default:
				log.warning('Not expecting response type ('+msg.type+')');
				break;
		}
	});
};

//>>>
m2.authenticator.prototype.generate_key = function(bytes) { //<<<
	var csprng;
	if (typeof bytes == 'undefined') {
		bytes = 56;
	}
	csprng = new cfcrypto.csprng();
	return csprng.getbytes(bytes);
};

//>>>
m2.authenticator.prototype._crypt_setup = function() { //<<<
	var pending_cookie, n, e, e_key, e_cookie, self, tmp;

	pending_cookie = this.generate_key();

	n = this._pubkey.n;
	e = this._pubkey.e;
	e_key = cfcrypto.rsa.RSAES_OAEP_Encrypt(n, e, this._keys.main, "");
	e_cookie = cfcrypto.rsa.RSAES_OAEP_Encrypt(n, e, pending_cookie, "");

	self = this;
	tmp = serialize_tcl_list(['crypt_setup', e_key, e_cookie]);
	this.req('authenticator', tmp, function(msg) {
		var pdata, was_encrypted;
		try {
			switch (msg.type) {
				case 'ack':
				case 'jm':
					try {
						pdata = self.decrypt(self._keys.main, msg.data);
						was_encrypted = true;
					} catch(e) {
						log.error('error decrypting message: '+e);
						return;
					}
					break;

				default:
					pdata = msg.data;
					was_encrypted = false;
					break;
			}

			switch (msg.type) {
				case 'ack':
					if (pdata === pending_cookie) {
						self._signals.getItem('established').set_state(true);
					} else {
						log.error('cookie challenge from server did not match');
					}
					break;

				case 'nack':
					log.error('got nack: '+msg.data);
					break;

				case 'pr_jm':
					self.register_jm_key(msg.seq, self._keys.main);
					//log.debug('Got pr_jm: '+msg.seq+', registering key base64: '+self._keys.main);
					if (self.enc_chan === null) {
						self.enc_chan = msg.seq;
					} else {
						log.warning('already have enc_chan??');
					}
					break;

				case 'jm_can':
					self._signals.getItem('established').set_state(false);
					self.enc_chan = null;
					break;
			}
		} catch(e2) {
			log.warning('Error handling authenticator response ('+msg.type+'): '+e2);
		}
	});
};

//>>>
m2.authenticator.prototype._login_resp_pr_jm = function(msg) { //<<<
	var tag, parts, self, defined_profiles, selected_profile, key, heartbeat_interval, connected_users, i;

	self = this;
	parts = parse_tcl_list(msg.data);
	tag = parts[0];
	switch (tag) {
		case 'login_chan':
			if (this.login_chan === null) {
				log.debug('got login_chan pr_jm: seq: '+msg.seq+', prev_seq: '+msg.prev_seq);
				this.login_chan = [msg.seq, msg.prev_seq];
			} else {
				log.warning('got a login_chan pr_jm ('+msg.seq+') when we already have a login_chan set ('+this.login_chan+')');
			}
			break;

		case 'select_profile':
			defined_profiles = parse_tcl_list(parts[0]);
			if (defined_profiles.length == 2) {
				this.select_profile(msg.seq, defined_profiles[0]);
			} else {
				try {
					if (this.profile_cb === null) {
						log.warning('Asked to select a profile but no profile_cb was defined');
						this.select_profile(msg.seq, '');
					} else {
						this.profile_cb(msg.seq, defined_profiles);
					}
				} catch(e) {
					log.error('Unhandled error: '+e);
					this.select_profile(msg.seq, '');
				}
			}
			break;

		case 'perms':
		case 'prefs':
		case 'attribs':
			log.debug('got userinfo "'+tag+'" pr_jm: seq: '+msg.seq+', prev_seq: '+msg.prev_seq);
			key = msg.seq + '/' + msg.prev_seq;
			this.login_subchans.setItem(key, 'userinfo');
			this._update_userinfo(parts);
			break;

		case 'session_chan':
			log.debug('got session_chan pr_jm: seq: '+msg.seq+', prev_seq: '+msg.prev_seq);
			heartbeat_interval = parts[1];
			key = msg.seq + '/' + msg.prev_seq;
			// Isn't strictly a sub channel of login_chan...
			this.login_subchans.setItem(key, 'session_chan');
			if (heartbeat_interval !== '') {
				this._setup_heartbeat(heartbeat_interval, msg.seq);
			}
			break;

		case 'admin_chan':
			log.debug('got admin_chan pr_jm: seq: '+msg.seq+', prev_seq: '+msg.prev_seq);
			key = msg.seq + '/' + msg.prev_seq;
			// Isn't strictly a sub channel of login_chan...
			this.login_subchans.setItem(key, 'admin_chan');
			this.admin_info.admin_chan = key;
			this.admin_info.connected_users = new Hash();
			connected_users = parse_tcl_list(parts[1]);
			for (i=0; i<connected_users.length; i++) {
				this.admin_info.connected_users.setItem(connected_users[i], true);
			}
			break;

		default:
			key = msg.seq + '/' + msg.prev_seq;
			log.error('unknown login subchan: ('+key+') ('+tag+')');
			this.login_subchans.setItem(key, 'unknown');
			break;
	}
};

//>>>
m2.authenticator.prototype.select_profile = function(seq, selected_profile) { //<<<
	this.rsj_req(seq, serialize_tcl_list(['select_profile', selected_profile]),
		function(){});
};

//>>>
m2.authenticator.prototype._update_userinfo = function(data) { //<<<
	var i, permnames, attribs, prefs, self;

	self = this;

	switch (data[0]) {
		case 'perms':
			permnames = parse_tcl_list(data[1]);
			for (i=0; i<permnames.length; i++) {
				switch (permnames[i].charAt(0)) {
					case "-":
						this.perms.removeItem(permnames[i].substr(1));
						break;

					case "+":
						this.perms.setItem(permnames[i].substr(1), true);
						break;

					default:
						this.perms.setItem(permnames[i], true);
				}
			}
			this._signals.getItem('got_perms').set_state(true);
			break;

		case 'attribs':
			attribs = array2hash(parse_tcl_list(data[1]));
			attribs.forEach(function(attrib, value) {
				switch (attrib.charAt(0)) {
					case '-':
						self.attribs.removeItem(attrib.substr(1));
						break;

					case '+':
						self.attribs.setItem(attrib.substr(1), value);
						break;

					default:
						self.attribs.setItem(attrib, value);
						break;
				}
			});
			this._signals.getItem('got_attribs').set_state(true);
			break;

		case 'prefs':
			prefs = array2hash(parse_tcl_list(data[1]));
			prefs.forEach(function(pref, value) {
				switch (pref.charAt(0)) {
					case '-':
						self.prefs.removeItem(pref.substr(1));
						break;

					case '+':
						self.prefs.setItem(pref.substr(1), value);
						break;

					default:
						self.prefs.setItem(pref, value);
						break;
				}
			});
			this._signals.getItem('got_prefs').set_state(true);
			break;

		default:
			log.warning('unexpected update type: ('+data[0]+')');
			break;
	}
};

//>>>
m2.authenticator.prototype._setup_heartbeat = function(heartbeat_interval, session_jmid) { //<<<
	var self;

	heartbeat_interval -= 10;

	if (heartbeat_interval < 1) {
		log.warning('Very short heartbeat interval: '+heartbeat_interval);
		heartbeat_interval = 1;
	}

	self = this;
	this.heartbeat_afterid = setTimeout(function() {
		self._send_heartbeat(heartbeat_interval, session_jmid);
	}, heartbeat_interval * 1000);
};

//>>>
m2.authenticator.prototype._send_heartbeat = function(heartbeat_interval, session_jmid) { //<<<
	var self;
	this.rsj_req(session_jmid, serialize_tcl_list(['_heartbeat']), function(){});
	self = this;
	this.heartbeat_afterid = setTimeout(function() {
		self._send_heartbeat(heartbeat_interval, session_jmid);
	}, heartbeat_interval * 1000);
};

//>>>
m2.authenticator.prototype._admin_chan_update = function(data) { //<<<
	var op, new_user_fqun, old_user_fqun;

	op = data[0];

	switch (op) {
		case 'user_connected':
			new_user_fqun = data[1];
			if (!this.admin_info.connected_users.hasItem(new_user_fqun)) {
				this.admin_info.connected_users.setItem(new_user_fqun, true);
				if (typeof this.connected_users_changed != 'undefined') {
					this.connected_users_changed();
				}
			}
			break;

		case 'user_disconnected':
			old_user_fqun = data[1];
			if (this.admin_info.connected_users.hasItem(old_user_fqun)) {
				this.admin_info.connected_users.removeItem(old_user_fqun);
				if (typeof this.connected_users_changed != 'undefined') {
					this.connected_users_changed();
				}
			}
			break;

		default:
			log.warning('Unrecognised admin update: ('+op+')');
			break;
	}
};

//>>>

// vim: ft=javascript foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
