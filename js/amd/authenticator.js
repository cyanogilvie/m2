/*global define */
/*jslint nomen: true, plusplus: true, white: true, browser: true, node: true, newcap: true, continue: true */

define([
	'dojo/_base/declare',
	'./m2',
	'cf/sop/signal',
	'cf/sop/gate',
	'cf/log',
	'cf/jsbn/BigInteger',
	'cf/cfcrypto/cfcrypto',
	'cf/tcllist/tcllist'
], function(
	declare,
	m2,
	Signal,
	Gate,
	log,
	BigInteger,
	cfcrypto,
	tcllist
){
"use strict";

return declare([m2], {
	pbkey: null,

	// Set this to something that initiates a profile selection process
	// with the user, and calls this.select_profile(seq, profilename) when done.
	// Callback is passed the arguments (seq, profiles_available_dict)
	profile_cb: null,
	default_domain: null,

	constructor: function(){
		if (!this.pbkey) {
			throw new Error('Must supply pbkey');
		}
	},

	destructor: function(){
		var self;
		self = this;

		this._signals.available = this.svc_signal('authenticator');
		this._signals.established = new Signal({name: 'established'});
		this._signals.authenticated = new Signal({name: 'authenticated'});
		this._signals.login_pending = new Gate({name: 'login_pending', mode: 'and'});
		this._signals.login_allowed = new Gate({name: 'login_allowed', mode: 'and'});
		this._signals.got_perms = new Signal({name: 'got_perms'});
		this._signals.got_attribs = new Signal({name: 'got_attribs'});
		this._signals.got_prefs = new Signal({name: 'got_prefs'});

		this._signals.login_allowed.attach_input(
			this._signals.login_pending, 'inverted');
		this._signals.login_allowed.attach_input(
			this._signals.authenticated, 'inverted');
		this._signals.login_allowed.attach_input(
			this._signals.established);

		this._signals.connected.attach_output(function(newstate) {
			if (!newstate) {
				// Reset login_pending if our connection is dropped while a
				// login request was in flight
				self._signals.login_pending.set_state(false);
			}
		});

		this.connected_users_changed = null;

		this._pubkey = this._load_pbkey(this.pbkey);
		this._keys = {};
		this._keys.main = this.generate_key();
		this.enc_chan = null;
		this.login_chan = null;
		this._fqun = null;
		this.session_prkey = null;
		this.login_subchans = {};
		this.perms = {};
		this.attribs = {};
		this.prefs = {};
		this.admin_info = {};
		this.session_pbkey_chan = null;
		this.last_login_message = '';

		// TODO: no longer needed I think
		this._signals.connected.attach_output(function(newstate) {
			if (!newstate) {
				self._signals.available.set_state(false);
			}
		});

		this._signals.available.attach_output(function(newstate) {
			if (newstate) {
				self._crypt_setup();
			} else {
				self._signals.established.set_state(false);
			}
		});
	},

	destroy: function() {
	},

	_load_pbkey: function(pbkey) {
		var K, l;

		l = tcllist.list2dict(pbkey);

		if (l.n === undefined || l.e === undefined) {
			throw new Error('Not a public key: '+pbkey);
		}

		K = {};
		K.n = new BigInteger(l.n, '10');
		K.e = new BigInteger(l.e, '10');

		return K;
	},

	login: function(username, password, cb) {
		var self = this;

		if (!this._signals.login_allowed.state()) {
			throw new Error('Cannot login at this time');
		}

		if (username.indexOf('@') === -1) {
			if (this.default_domain === null) {
				throw new Error('No domain specified and no default domain');
			}
			username += '@'+this.default_domain;
		}

		this._signals.login_pending.set_state(true);

		this.rsj_req(this.enc_chan, tcllist.array2list(['login', username, password]), function(msg) {
			var before, after, K, pbkey, key, parts, op;

			switch (msg.type) {
				case 'ack':
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
					self.rsj_req(self.login_chan[0], tcllist.array2list(['session_pbkey_update', tcllist.array2list(pbkey)]), function(msg) {
						switch (msg.type) {
							case 'ack':
								self._signals.authenticated.set_state(true);
								self._signals.login_pending.set_state(false);
								if (cb) {
									cb.call(null, true);
								}
								break;

							case 'nack':
								self._signals.login_pending.set_state(false);
								if (cb) {
									cb.call(null, false, msg.data);
								}
								break;

							case 'pr_jm':
								if (self.session_pbkey_chan !== null) {
									log.warn('Already have session_pbkey_chan: ('+self.session_pbkey_chan+')');
								}
								self.session_pbkey_chan = [msg.seq, msg.prev_seq];
								break;

							case 'jm':
								if (self.session_pbkey_chan === null || msg.seq !== self.session_pbkey_chan[0]) {
									log.warn('unrecognised jm chan: ('+msg.seq+')');
									return;
								}

								parts = tcllist.list2array(msg.data);
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

										self.rsj_req(self.session_pbkey_chan[0], tcllist.array2list(['session_pbkey_update', pbkey]), function(msg) {
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
								break;

							case 'jm_can':
								if (self.session_pbkey_chan !== null && self.session_pbkey_chan[0] === msg.seq) {
									self.session_pbkey_chan = null;
									self.logout();
								} else {
									log.error('error: non session_pbkey_chan jm cancelled');
								}
								break;

							default:
								log.error('Unexpected response type to session_pbkey_update request: ('+msg.type+')');
								break;
						}
					});
					break;

				case 'nack':
					self.last_login_message = msg.data;
					log.error('Error logging in: '+msg.data);
					self._signals.login_pending.set_state(false);
					if (cb) {
						cb.call(null, false, msg.data);
					}
					break;

				case 'pr_jm':
					self._login_resp_pr_jm(msg);
					break;

				case 'jm':
					key = msg.seq + '/' + msg.prev_seq;
					if (self.login_subchans[key] === undefined) {
						log.warning('not sure what to do with jm: ('+msg.svc+','+msg.seq+','+msg.prev_seq+') ('+msg.data+')');
						return;
					}

					switch (self.login_subchans[key]) {
						case 'userinfo':
							self._update_userinfo(tcllist.list2array(msg.data));
							break;

						case 'admin_chan':
							self._admin_chan_update(tcllist.list2array(msg.data));
							break;

						default:
							log.warning('registered but unhandled login subchan seq: ('+key+') type: ('+self.login_subchans[key]+')');
							break;
					}
					break;

				case 'jm_can':
					if (self.login_chan !== null && self.login_chan[0] === msg.seq) {
						self.login_chan = null;
						log.debug('Got login_chan cancel, calling logout');
						self.logout();
					} else {
						key = msg.seq + '/' + msg.prev_seq;
						if (self.login_subchans[key] !== undefined) {
							switch (self.login_subchans[key]) {
								case 'userinfo':
									log.debug('userinfo channel cancelled');
									self._signals.got_perms.set_state(false);
									self._signals.got_attribs.set_state(false);
									self._signals.got_prefs.set_state(false);

									self.perms = {};
									self.attribs = {};
									self.prefs = {};
									break;

								case 'admin_chan':
									log.debug('admin_chan cancelled');
									self.admin_info = {};
									break;

								case 'session_chan':
									log.debug('session_chan cancelled');
									break;

								default:
									log.warning('registered but unhandled login subchan cancel: seq: ('+msg.seq+') type: ('+self.login_subchans[key]+')');
									break;
							}
							delete self.login_subchans[key];
						} else {
							log.warning('unexpected jm_can: seq: ('+msg.seq+')');
						}
					}
					break;

				default:
					log.warning('Unexpected response type to login request: '+msg.type);
					break;
			}
		});
	},

	logout: function() {
		var key, value, parts;

		log.debug('In logout');
		if (!this._signals.authenticated.state()) {
			log.warning('Authenticator logout: not logged in');
			return;
		}
		if (this.login_chan !== null) {
			log.debug('Sending login_chan jm_disconnect: seq: '+this.login_chan[0]+', prev_seq: '+this.login_chan[1]);
			this.jm_disconnect(this.login_chan[0], this.login_chan[1]);
			this.login_chan = null;
		}
		for (key in this.login_subchans) {
			if (this.login_subchans.hasOwnProperty(key)) {
				value = this.login_subchans[key];
				parts = key.split('/');
				log.debug('Sending login subchan disconnect: seq: '+parts[0]+', prev_seq: '+parts[1]);
				this.jm_disconnect(parts[0], parts[1]);
				switch (value) {
					case 'userinfo':
						this._signals.got_perms.set_state(false);
						this._signals.got_attribs.set_state(false);
						this._signals.got_prefs.set_state(false);

						this.perms = {};
						this.attribs = {};
						this.prefs = {};
						break;

					case 'admin_chan':
						this.admin_info = {};
						break;

					case 'session_chan':
						break;

					default:
						log.warning('Cancelled unhandled login subchan type "'+value+'"');
						break;
				}
			}
		}
		this.login_subchans = {};
		if (this.session_pbkey_chan !== null) {
			log.debug('Sending session_pbkey_chan jm_disconnect: seq: '+this.session_pbkey_chan[0]+', prev_seq: '+this.session_pbkey_chan[1]);
			this.jm_disconnect(this.session_pbkey_chan[0], this.session_pbkey_chan[1]);
			this.session_pbkey_chan = null;
		}
		this._signals.authenticated.set_state(false);
	},

	get_svc_pbkey: function(svc, cb) {
		if (!this._signals.authenticated.state()) {
			throw new Error('Not authenticated yet');
		}

		this.rsj_req(this.login_chan[0], tcllist.array2list(['get_svc_pubkey', svc]), function(msg) {
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
	},

	connect_svc: function(svc) {
		return new m2.connector(this, svc);
	},

	decrypt_with_session_prkey: function(data) {
		return cfcrypto.rsa.RSAES_OAEP_Decrypt(this.session_prkey, data, '');
	},

	fqun: function() {
		if (!this._signals.authenticated.state()) {
			throw new Error('Not authenticated yet');
		}
		return this._fqun;
	},

	get_user_pbkey: function(fqun, cb) {
		// Don't think this is needed on the client side.  I don't envision
		// implementing components in javascript
		if (!this._signals.established.state()) {
			throw new Error('No encrypted channel to the authenticator established yet');
		}
		//log.debug('sending request on '+this.enc_chan);
		this.rsj_req(this.enc_chan, tcllist.array2list(['get_user_pbkey', fqun]), function(msg) {
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
	},

	last_login_message: function() {
		return this.last_login_message;
	},

	auth_chan_req: function(data, cb) {
		if (this._signals.authenticated.state()) {
			throw new Error('Not authenticated yet');
		}

		this.rsj_req(this.login_chan[0], data, cb);
	},

	enc_chan_req: function(data, cb) {
		// Unneeded in client side api
		throw new Error('enc_chan_req not supported in javascript implementation');
	},

	perm: function(perm) {
		if (!this._signals.got_perms.state()) {
			throw new Error('Haven\'t received perms yet');
		}
		return this.perms[perm] !== undefined;
	},

	attrib: function(attrib, default_value) {
		if (!this._signals.got_attribs.state()) {
			throw new Error('Haven\'t received attribs yet');
		}
		if (this.attribs[attrib] !== undefined) {
			return this.attribs[attrib];
		} else {
			if (default_value !== undefined) {
				log.debug('attrib not set, using fallback');
				return default_value;
			} else {
				throw new Error('No attrib ('+attrib+') defined');
			}
		}
	},

	pref: function(pref, default_value) {
		if (!this._signals.got_prefs.state()) {
			throw new Error('Haven\'t received prefs yet');
		}
		if (this.prefs[pref] !== undefined) {
			return this.prefs[pref];
		} else {
			if (default_value !== undefined) {
				return default_value;
			} else {
				throw new Error('No pref ('+pref+') defined');
			}
		}
	},

	set_pref: function(pref, newvalue) {
		if (!this._signals.authenticated.state()) {
			throw new Error('Not authenticated yet');
		}
		this.rsj_req(this.login_chan[0], tcllist.array2list(['set_pref', pref, newvalue]), function(msg) {
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
	},

	change_password: function(old, new1, new2) {
		if (!this._signals.authenticated.state()) {
			throw new Error('Not authenticated yet');
		}

		this.rsj_req(this.login_chan[0], tcllist.array2list(['change_password', old, new1, new2]), function(msg) {
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
	},

	is_admin: function() {
		if (!this._signals.authenticated.state()) {
			throw new Error('Not authenticated yet');
		}
		return this.perm('system.admin');
	},

	get_admin_info: function() {
		return this.admin_info;
	},

	admin: function(op, data, cb) {
		if (!this.is_admin()) {throw new Error('Not an administrator');}

		this.rsj_req(this.admin_info.admin_chan[0], tcllist.array2list([op, data]), function(msg) {
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
	},

	generate_key: function(bytes) {
		var csprng;
		if (bytes === undefined) {
			bytes = 56;
		}
		csprng = new cfcrypto.csprng();
		return csprng.getbytes(bytes);
	},

	_crypt_setup: function() {
		var pending_cookie, n, e, e_key, e_cookie, self, tmp;

		pending_cookie = this.generate_key();

		n = this._pubkey.n;
		e = this._pubkey.e;
		e_key = cfcrypto.rsa.RSAES_OAEP_Encrypt(n, e, this._keys.main, "");
		e_cookie = cfcrypto.rsa.RSAES_OAEP_Encrypt(n, e, pending_cookie, "");

		self = this;
		tmp = tcllist.array2list(['crypt_setup', e_key, e_cookie]);
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
							self._signals.established.set_state(true);
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
						self._signals.established.set_state(false);
						self.enc_chan = null;
						break;
				}
			} catch(e2) {
				log.warning('Error handling authenticator response ('+msg.type+'): '+e2);
			}
		});
	},

	_login_resp_pr_jm: function(msg) {
		var tag, parts, self, defined_profiles, key, heartbeat_interval, connected_users, i;

		self = this;
		parts = tcllist.list2array(msg.data);
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
				defined_profiles = tcllist.list2array(parts[0]);
				if (defined_profiles.length === 2) {
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
				this.login_subchans[key] = 'userinfo';
				this._update_userinfo(parts);
				break;

			case 'session_chan':
				log.debug('got session_chan pr_jm: seq: '+msg.seq+', prev_seq: '+msg.prev_seq);
				heartbeat_interval = parts[1];
				key = msg.seq + '/' + msg.prev_seq;
				// Isn't strictly a sub channel of login_chan...
				this.login_subchans[key] = 'session_chan';
				if (heartbeat_interval !== '') {
					this._setup_heartbeat(heartbeat_interval, msg.seq);
				}
				break;

			case 'admin_chan':
				log.debug('got admin_chan pr_jm: seq: '+msg.seq+', prev_seq: '+msg.prev_seq);
				key = msg.seq + '/' + msg.prev_seq;
				// Isn't strictly a sub channel of login_chan...
				this.login_subchans[key] = 'admin_chan';
				this.admin_info.admin_chan = key;
				this.admin_info.connected_users = {};
				connected_users = tcllist.list2array(parts[1]);
				for (i=0; i<connected_users.length; i++) {
					this.admin_info.connected_users[connected_users[i]] = true;
				}
				break;

			default:
				key = msg.seq + '/' + msg.prev_seq;
				log.error('unknown login subchan: ('+key+') ('+tag+')');
				this.login_subchans[key] = 'unknown';
				break;
		}
	},

	select_profile: function(seq, selected_profile) {
		this.rsj_req(seq, tcllist.array2list(['select_profile', selected_profile]),
			function(){});
	},

	_update_userinfo: function(data) {
		var i, permnames, attribs, prefs, attrib, value, pref;

		switch (data[0]) {
			case 'perms':
				permnames = tcllist.list2array(data[1]);
				for (i=0; i<permnames.length; i++) {
					switch (permnames[i].charAt(0)) {
						case "-":
							delete this.perms[permnames[i].substr(1)];
							break;

						case "+":
							this.perms[permnames[i].substr(1)] = true;
							break;

						default:
							this.perms[permnames[i]] = true;
					}
				}
				this._signals.got_perms.set_state(true);
				break;

			case 'attribs':
				attribs = tcllist.list2dict(data[1]);
				for (attrib in attribs) {
					if (attribs.hasOwnProperty(attrib)) {
						value = attribs[attrib];
						switch (attrib.charAt(0)) {
							case '-':
								delete this.attribs[attrib.substr(1)];
								break;

							case '+':
								this.attribs[attrib.substr(1)] = value;
								break;

							default:
								this.attribs[attrib] = value;
								break;
						}
					}
				}
				this._signals.got_attribs.set_state(true);
				break;

			case 'prefs':
				prefs = tcllist.list2dict(data[1]);

				for (pref in prefs) {
					if (prefs.hasOwnProperty(pref)) {
						value = prefs[pref];
						switch (pref.charAt(0)) {
							case '-':
								delete this.prefs[pref.substr(1)];
								break;

							case '+':
								this.prefs[pref.substr(1)] = value;
								break;

							default:
								this.prefs[pref] = value;
								break;
						}
					}
				}
				this._signals.got_prefs.set_state(true);
				break;

			default:
				log.warning('unexpected update type: ('+data[0]+')');
				break;
		}
	},

	_setup_heartbeat: function(heartbeat_interval, session_jmid) {
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
	},

	_send_heartbeat: function(heartbeat_interval, session_jmid) {
		var self = this;
		this.rsj_req(session_jmid, tcllist.array2list(['_heartbeat']), function(){});
		this.heartbeat_afterid = setTimeout(function() {
			self._send_heartbeat(heartbeat_interval, session_jmid);
		}, heartbeat_interval * 1000);
	},

	_admin_chan_update: function(data) {
		var op, new_user_fqun, old_user_fqun;

		op = data[0];

		switch (op) {
			case 'user_connected':
				new_user_fqun = data[1];
				if (this.admin_info.connected_users[new_user_fqun] === undefined) {
					this.admin_info.connected_users[new_user_fqun] = true;
					if (this.connected_users_changed !== undefined) {
						this.connected_users_changed();
					}
				}
				break;

			case 'user_disconnected':
				old_user_fqun = data[1];
				if (this.admin_info.connected_users[old_user_fqun] !== undefined) {
					delete this.admin_info.connected_users[old_user_fqun];
					if (this.connected_users_changed !== undefined) {
						this.connected_users_changed();
					}
				}
				break;

			default:
				log.warning('Unrecognised admin update: ('+op+')');
				break;
		}
	}
});
});
