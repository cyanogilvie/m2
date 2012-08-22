/*global define */
/*jslint nomen: true, plusplus: true, white: true, browser: true, node: true, newcap: true, continue: true */

define([
	'dojo/_base/declare',
	'sop/signalsource',
	'sop/signal',
	'sop/gate',
	'sop/domino',
	'cflib/log',
	'cfcrypto/csprng',
	'cfcrypto/crypto',
	'cfcrypto/blowfish',
	'tcl/list'
], function(
	declare,
	Signalsource,
	Signal,
	Gate,
	Domino,
	log,
	csprng,
	rsa,
	Blowfish,
	tcllist
){
"use strict";

return declare([Signalsource], {
	auth: null,
	svc: null,

	_pbkey: null,
	_e_chan: null,
	_e_chan_prev_seq: null,
	_skey: null,
	_cookie: null,
	_signal_hooks: null,

	constructor: function() {
		var self = this;

		if (this.auth === null) {
			console.log('connector constructor this: arguments:', arguments,', ', this);
			throw new Error('connector: Must supply auth');
		}
		if (this.svc === null) {
			throw new Error('connector: Must supply svc');
		}

		this._signals.available = this.auth.svc_signal(this.svc);
		this._signals.connected = new Signal({name: this.svc+' connected'});
		this._signals.authenticated = new Signal({name: this.svc+' authenticated'});
		this._signals.got_svc_pbkey = new Signal({name: this.svc+' got_svc_pbkey'});
		this._signals.connect_ready = new Gate({name: this.svc+' connect_ready', mode: 'and'});
		this.dominos = {};
		this.dominos.need_reconnect = new Domino({name: this.svc+' reconnect'});

		this._signals.connect_ready.attach_input(this.auth.signal_ref('authenticated'));
		this._signals.connect_ready.attach_input(this._signals.got_svc_pbkey);
		this._signals.connect_ready.attach_input(this._signals.available);

		this._signal_hooks = {};
		this._signal_hooks.authenticated_changed = this.auth.signal_ref('authenticated').attach_output(function(newstate){
			self._authenticated_changed(newstate);
		});
		this.dominos.need_reconnect.attach_output(function(){
			self._reconnect();
		});
		this._signals.connect_ready.attach_output(function(newstate){
			self._connect_ready_changed(newstate);
		});
	},

	destroy: function() {
		// TODO: the stuff that goes here
		this.auth.signal_ref('authenticated').detach_output(this._signal_hooks.authenticated_changed);
		this.dominos.need_reconnect.destroy();
		this.dominos.need_reconnect = null;
		this._signals.connect_ready.destroy();
		this._signals.connect_ready = null;
		this.disconnect();
	},

	req_async: function(op, data, cb) {
		if (!this._signals.authenticated.state()) {
			throw new Error('Cannot issue request - not authenticated yet');
		}
		return this.auth.rsj_req(this._e_chan, tcllist.array2list([op, data]), cb);
	},

	chan_req_async: function(jmid, data, cb) {
		if (!this._signals.authenticated.state()) {
			throw new Error('Cannot issue request - not authenticated yet');
		}
		return this.auth.rsj_req(jmid, data, cb);
	},

	jm_disconnect: function(seq, prev_seq) {
		return this.auth.jm_disconnect(seq, prev_seq);
	},

	disconnect: function() {
		if (this._signals.connected.state()) {
			this._signals.authenticated.set_state(false);
			this._signals.connected.set_state(false);
			if (this._e_chan !== null) {
				this.jm_disconnect(this._e_chan, this._e_chan_prev_seq);
				this._e_chan = null;
				this._e_chan_prev_seq = null;
			}
		}
	},

	unique_id: function() {
		return this.auth.unique_id();
	},

	_connect_ready_changed: function(newstate) {
		if (newstate) {
			//log.debug('setting reconnect in motion');
			this.dominos.need_reconnect.tip();
		}
	},

	_reconnect: function() {
		var skey, cookie, n, e, msg, ks, iv, tail, self;

		log.debug('reconnecting to '+this.svc);
		if (this._signals.connected.state()) {
			this.disconnect();
		}

		skey = this.auth.generate_key();
		cookie = csprng.getbytes(8);
		//log.debug('this._pbkey: ', this._pbkey);
		n = this._pbkey.n;
		e = this._pbkey.e;
		//log.debug('n bitlength: '+n.bitLength());
		//log.debug('Encrypting session key with n: '+n.toString(16)+', e: '+e.toString(16));
		msg = rsa.RSAES_OAEP_Encrypt(n, e, skey, "");
		//log.debug('skey base64: '+Base64.encode(skey));
		//log.debug('reconnect msg length: '+msg.length+' base64 e_skey: '+Base64.encode(msg));
		ks = new Blowfish(skey);
		iv = csprng.getbytes(8);
		tail = ks.encrypt_cbc(tcllist.array2list([cookie, this.auth.fqun(), iv]), iv);
		this._skey = skey;
		this._cookie = cookie;

		self = this;
		//log.debug('"setup " cookie base64: '+Base64.encode(cookie));
		this.auth.req(this.svc, 'setup '+tcllist.array2list([msg, tail, iv]), function(msg){
			self._resp(msg);
		});
	},

	_resp: function(msg) {
		var svc_cookie, self, pdata;

		self = this;

		switch (msg.type) {
			case 'ack':
				if (this._e_chan === null) {
					log.error('Incomplete encrypted channel setup: got ack but no pr_jm');
					return;
				}
				this._signals.connected.set_state(true);
				//log.debug('msg.data.length: '+msg.data.length+' msg.data: (e_cookie2 base64) '+Base64.encode(msg.data));
				svc_cookie = this.auth.decrypt_with_session_prkey(msg.data);
				//log.debug('Got cookie2: base64: '+Base64.encode(svc_cookie));
				//log.debug('sending proof of identity');
				this.auth.rsj_req(this._e_chan, svc_cookie, function(msg){
					self._auth_resp(msg);
				});
				break;

			case 'nack':
				if (this._e_chan !== null) {
					this._e_chan = null;
				}
				if (this._e_chan_prev_seq !== null) {
					this._e_chan_prev_seq = null;
				}
				log.error('Got nacked: ('+msg.data+')');
				break;

			case 'pr_jm':
				if (this._e_chan === null) {
					pdata = this.auth.decrypt(this._skey, msg.data);
					if (pdata === this._cookie) {
						this._e_chan = msg.seq;
						this._e_chan_prev_seq = msg.prev_seq;
						//log.debug('got matching cookie, storing e_chan ('+this._e_chan+') and registering it with auth::register_jm_key');
						this.auth.register_jm_key(this._e_chan, this._skey);
					} else {
						//log.error('did not get correct response from component: expecting: ('+Base64.encode(this._cookie)+')['+this._cookie.length+'] got: ('+Base64.encode(pdata)+')['+pdata.length+']');
						log.error('did not get correct response from component');
					}
				}
				break;

			case 'jm_can':
				if (this._e_chan !== null && this._e_chan === msg.seq) {
					this._signals.connected.set_state(false);
					this._signals.authenticated.set_state(false);
					this._e_chan = null;
					this._e_chan_prev_seq = null;
				}
				break;

			default:
				log.warning('Not expecting response type ('+msg.type+')');
				break;
		}
	},

	_auth_resp: function(msg) {
		switch (msg.type) {
			case 'ack':
				//log.debug('got ack: ('+msg.data+')');
				this._signals.authenticated.set_state(true);
				break;

			case 'nack':
				log.error('got nack: ('+msg.data+')');
				break;

			default:
				log.error('unexpected type: ('+msg.type+')');
				break;
		}
	},

	_authenticated_changed: function(newstate) {
		var self;

		if (newstate) {
			//log.debug('requesting public key for ('+this.svc+') ...');
			self = this;
			this.auth.get_svc_pbkey(this.svc, function(ok, data) {
				if (ok) {
					self._pbkey_asc = data;
					//log.debug('got public key ascii format for ('+self.svc+'), loading into key ...');
					try {
						//log.debug('Attempting to extract public key from: '+self._pbkey_asc);
						self._pbkey = rsa.load_asn1_pubkey_from_value(self._pbkey_asc);
						//log.debug('got public key for ('+self.svc+')');
						//log.debug('self._pbkey: ', self._pbkey);
						self._signals.got_svc_pbkey.set_state(true);
					} catch(e) {
						log.error('error decoding public key for ('+self.svc+'): '+e+'\n'+e.stack);
					}
				} else {
					log.error('error fetching public key for ('+self.svc+'): '+data);
				}
			});
		} else {
			this._signals.got_svc_pbkey.set_state(false);
			if (this._pbkey !== null) {
				this._pbkey = null;
			}
		}
	}
});
});
