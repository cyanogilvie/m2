/*global define */
/*jslint nomen: true, plusplus: true, white: true, browser: true, node: true, newcap: true, continue: true */

define([
	'dojo/_base/declare',
	'cf/sop/signalsource',
	'cf/sop/signal',
	'cf/log',
	'cf/jsSocket',
	'cf/webtoolkit/utf8',
	'cf/webtoolkit/base64',
	'cf/cfcrypto/cfcrypto',
	'cf/tcllist/tcllist',
	'cf/evlog/evlog'
], function(
	declare,
	Signalsource,
	Signal,
	log,
	jsSocket,
	Utf8,
	Base64,
	cfcrypto,
	tcllist,
	evlog
){
"use strict";

return declare([Signalsource], {
	host: null,
	port: null,

	_unique_id: 0,
	_handlers: null,
	_event_handlers: null,
	_pending: null,
	_ack_pend: null,
	_jm: null,
	_jm_prev_seq: null,
	_socket: null,
	_signals: null,
	_svcs: null,
	_svc_signals: null,
	_defrag_buf: null,
	_msgid_seq: 0,
	_queues: null,
	_jm_keys: null,
	_key_schedules: null,
	_pending_keys: null,

	constructor: function() {
		var self = this, t = [];

		if (!this.host) {
			this.host = window.location.hostname;
		}
		if (!this.port) {
			this.port = 5301;
		}

		this._handlers = {};
		this._event_handlers = {};
		this._pending = {};
		this._ack_pend = {};
		this._jm = {};
		this._jm_prev_seq = {};
		this._signals = {};
		this._svcs = {};
		this._svc_signals = {};
		this._defrag_buf = {};
		this._queues = {};
		this._jm_keys = {};
		this._key_schedules = {};
		this._pending_keys = {};

		if (t.indexOf === undefined) {
			this._arr_indexOf = function(arr, item) {
				var i;
				for (i=0; i<arr.length; i++) {
					if (item === arr[i]) {
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
		this._signals.connected = new Signal({name: 'connected'});

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
	},

	destroy: function() {
		this._socket.close();
	},

	svc_signal: function(svc) {
		var sig;
		if (!this._svc_signals[svc]) {
			sig = new Signal({
				name: 'svc_avail_'+svc
			});
			sig.set_state(this.svc_avail(svc));
			this._svc_signals[svc] = {
				sig: sig,
				svc: svc
			};
		}
		return this._svc_signals[svc].sig;
	},

	svc_avail: function(svc) {
		return this._svcs[svc] !== undefined;
	},

	req: function(svc, data, cb, withkey) {
		var seq;

		seq = this._unique_id++;

		if (withkey !== undefined) {
			data = this.encrypt(withkey, data);
		}

		this._send({
			svc:	svc,
			type:	'req',
			seq:	seq,
			data:	data
		});

		window.udata = Utf8.encode(data);
		this._pending[seq] = cb;
		this._ack_pend[seq] = 1;
		this._jm[seq] = 0;

		return seq;
	},

	rsj_req: function(jm_seq, data, cb) {
		var seq, e_data, key;

		seq = this._unique_id++;

		if (this._jm_keys[jm_seq] !== undefined) {
			key = this._jm_keys[jm_seq];
			this._pending_keys[seq] = key;
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

		this._pending[seq] = cb;
		this._ack_pend[seq] = 1;
		this._jm[seq] = 0;

		return seq;
	},

	jm_disconnect: function(jm_seq, prev_seq) {
		var idx, pseq_tmp, i, new_prev_seqs, old_prev_seqs;

		this._send({
			svc:		'',
			type:		'jm_disconnect',
			seq:		jm_seq,
			prev_seq:	prev_seq,
			data:		''
		});

		if (this._jm_prev_seq[jm_seq] !== undefined) {
			pseq_tmp = this._jm_prev_seq[jm_seq];
			idx = this._arr_indexOf(pseq_tmp, prev_seq);

			if (idx >= 0) {
				this._jm[prev_seq] = this._jm[prev_seq] - 1;
				if (this._jm[prev_seq] <= 0) {
					delete this._pending[prev_seq];
					delete this._jm[prev_seq];
				}
				new_prev_seqs = [];
				old_prev_seqs = this._jm_prev_seq[jm_seq];
				for (i=0; i<old_prev_seqs.length; i++) {
					if (old_prev_seqs[i] !== prev_seq) {
						new_prev_seqs.push(old_prev_seqs[i]);
					}
				}
				if (new_prev_seqs.length > 0) {
					this._jm_prev_seq[jm_seq] = new_prev_seqs;
				} else {
					delete this._jm_prev_seq[jm_seq];
				}
			}
		}
	},

	register_jm_key: function(jm_seq, key) {
		//log.debug('Registering jm_key for '+jm_seq+', base64: '+Base64.encode(key));
		this._jm_keys[jm_seq] = key;
	},

	encrypt: function(key, data) {
		var ks, iv, csprng;

		if (this._key_schedules[key] === undefined) {
			this._key_schedules[key] = new cfcrypto.blowfish(key);
		}
		ks = this._key_schedules[key];
		csprng = new cfcrypto.csprng();
		iv = csprng.getbytes(8);

		return iv+ks.encrypt_cbc(data, iv);
	},

	decrypt: function(key, data, hint) {
		var ks, iv, rest;

		if (this._key_schedules[key] === undefined) {
			this._key_schedules[key] = new cfcrypto.blowfish(key);
		}
		ks = this._key_schedules[key];
		iv = data.substr(0, 8);
		rest = data.substr(8);

		//log.debug('Decrypting msg with iv: '+Base64.encode(iv)+', key: '+Base64.encode(key), ', hint: '+hint);

		return ks.decrypt_cbc(rest, iv);
	},

	listen_event: function(event, cb) {
		if (!this._event_handlers[event]) {
			this._event_handlers[event] = [];
		}
		this._event_handlers[event].push(cb);
	},

	_gotMsg: function(reqseq, type, payload) {
		if (this._handlers[reqseq]) {
			this._handlers[reqseq](type, payload);
			if (type === 'ack' || type === 'nack') {
				delete this._handlers[reqseq];
			}
		}
	},

	_set_default_msg_fields: function(msg) {
		if (msg.svc === undefined)		{msg.svc		= 'sys';}
		if (msg.type === undefined)		{msg.type		= 'req';}
		if (msg.seq === undefined)		{msg.seq		= '';}
		if (msg.prev_seq === undefined)	{msg.prev_seq	= '0';}
		if (msg.meta === undefined)		{msg.meta		= '';}
		if (msg.oob_type === undefined)	{msg.oob_type	= '1';}
		if (msg.oob_data === undefined)	{msg.oob_data	= '1';}
	},

	_receive_msg: function(msg_raw) {
		var lineend, pre_raw, pre, fmt, hdr_len, data_len, hdr, data, ofs, msg;
		//log.debug('received complete message: ('+msg_raw+')');

		lineend = msg_raw.indexOf("\n");
		if (lineend === -1) {
			throw new Error('corrupt m2 message header: '+msg_raw);
		}
		pre_raw = msg_raw.substr(0, lineend);
		pre = tcllist.list2array(pre_raw);
		fmt = pre[0];
		if (fmt !== 1) {
			throw new Error('Cannot parse m2 message serialization format: ('+fmt+')');
		}
		hdr_len = Number(pre[1]);
		data_len = Number(pre[2]);
		hdr = tcllist.list2array(msg_raw.substr(lineend + 1, hdr_len));
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
			svc:		hdr[0],
			type:		hdr[1],
			seq:		hdr[2],
			prev_seq:	hdr[3],
			meta:		hdr[4],
			oob_type:	hdr[5],
			oob_data:	hdr[6],
			data:		data
		};
		this._got_msg(msg);
	},

	_svc_avail: function(new_svcs) {
		var i, e;

		for (i=0; i<new_svcs.length; i++) {
			this._svcs[new_svcs[i]] = true;
		}

		for (e in this._svc_signals) {
			if (this._svc_signals.hasOwnProperty(e)) {
				this._svc_signals[e].sig.set_state(this._svcs[this._svc_signals[e].svc]);
			}
		}

		// TODO: replace with dojo events ie. on(api, 'svc_avail_changed', ...)
		this._dispatch_event('svc_avail_changed', this._svcs);
	},

	_svc_revoke: function(revoked_svcs) {
		var i, e;

		for (i=0; i<revoked_svcs.length; i++) {
			delete this._svcs[revoked_svcs[i]];
		}

		for (e in this._svc_signals) {
			if (this._svc_signals.hasOwnProperty(e)) {
				this._svc_signals[e].sig.set_state(this._svcs[this._svc_signals[e].svc]);
			}
		}

		// TODO: replace with dojo events ie. on(api, 'svc_avail_changed', ...)
		this._dispatch_event('svc_avail_changed', this._svcs);
	},

	_jm_can: function(msg) {
		var prev_seq_arr, i, tmp, prev_seq, cb;

		delete this._jm_prev_seq[msg.seq];

		prev_seq_arr = tcllist.list2array(msg.prev_seq);

		for (i=0; i<prev_seq_arr.length; i++) {
			prev_seq = prev_seq_arr[i];
			tmp = this._jm[prev_seq]--;
			if (this._pending[prev_seq] !== undefined) {
				cb = this._pending[prev_seq];
				if (cb) {
					try {
						cb(msg, prev_seq);
					} catch(e) {
						log.error('error calling callback for jm_can: '+e);
					}
				}
			}
			if (this._jm[prev_seq] <= 0) {
				delete this._pending[prev_seq];
				delete this._jm[prev_seq];
			}
		}
	},

	_copy_msg: function(in_msg) {
		var e, out_msg = {};

		for (e in in_msg) {
			if (in_msg.hasOwnProperty(e)) {
				out_msg[e] = in_msg[e];
			}
		}

		return out_msg;
	},

	_response: function(msg) {
		//log.debug('_response: ', msg);
		var prev_seq_arr, i, prev_seq, cb, msgcopy;

		msgcopy = this._copy_msg(msg);
		prev_seq_arr = tcllist.list2array(msg.prev_seq);
		for (i=0; i<prev_seq_arr.length; i++) {
			prev_seq = prev_seq_arr[i];
			msgcopy.prev_seq = prev_seq;
			if (this._pending[prev_seq] !== undefined) {
				cb = this._pending[prev_seq];
				if (cb) {
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
			if (this._jm[prev_seq] === undefined) {
				continue;
			}
			if (
				this._jm[prev_seq] <= 0 &&
				this._ack_pend[prev_seq] === undefined
			) {
				delete this._pending[prev_seq];
				delete this._jm[prev_seq];
			}
		}
	},

	_evlog_msg: function(msg) {
		return tcllist.array2list([
			'svc',		msg.svc,
			'type',		msg.type,
			'seq',		msg.seq,
			'prev_seq',	msg.prev_seq,
			'meta',		msg.meta,
			'oob_type',	msg.oob_type,
			'oob_data',	msg.oob_data,
			'data',		msg.data
		]);
	},

	_got_msg: function(msg) {
		var key;
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
		evlog.event('m2.receive_msg', tcllist.array2list([
			'from', this.host+':'+this.port,
			'msg', this._evlog_msg(msg)
		]));

		// Decrypt any encrypted data, store jm_keys for new jm channels <<<
		switch (msg.type) {
			case 'ack':
				delete this._ack_pend[msg.prev_seq];
				if (this._pending_keys[msg.prev_seq] !== undefined) {
					msg.data = this.decrypt(this._pending_keys[msg.prev_seq], msg.data, 'ack of '+msg.prev_seq);
					delete this._pending_keys[msg.prev_seq];
				}
				break;

			case 'nack':
				delete this._ack_pend[msg.prev_seq];
				delete this._pending_keys[msg.prev_seq];
				break;

			case 'pr_jm':
				this._jm[msg.prev_seq]++;

				if (this._jm_prev_seq[msg.seq] === undefined) {
					this._jm_prev_seq[msg.seq] = [msg.prev_seq];
				} else if (this._arr_indexOf(this._jm_prev_seq[msg.seq], msg.prev_seq) === -1) {
					if (this._jm_prev_seq[msg.seq].push === undefined) {
						log.error('something went badly wrong with jm_prev_seq('+msg.seq+'): ', this._jm_prev_seq[msg.seq]);
					} else {
						this._jm_prev_seq[msg.seq].push(msg.prev_seq);
					}
					/*
					this._jm_prev_seq[msg.seq] =
						this._jm_prev_seq[msg.seq].push(msg.prev_seq);
					*/
				}

				if (this._pending_keys[msg.prev_seq] !== undefined) {
					msg.data = this.decrypt(this._pending_keys[msg.prev_seq], msg.data, 'pr_jm for '+msg.seq+', resp to '+msg.prev_seq);
					if (this._jm_keys[msg.seq] === undefined) {
						if (msg.data.length !== 56) {
							log.warning('pr_jm: dubious looking key: ('+Base64.encode(msg.data)+')');
						}
						this.register_jm_key(msg.seq, msg.data);
						return;
					} else {
						if (msg.data.length === 56) {
							if (msg.data === this._jm_keys[msg.seq]) {
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
				if (this._jm_keys[msg.seq] !== undefined) {
					msg.data = this.decrypt(this._jm_keys[msg.seq], msg.data, 'jm '+msg.seq);
				}
				break;

			case 'jm_req':
				if (this._jm_keys[msg.prev_seq] !== undefined) {
					msg.data = this.decrypt(this._jm_keys[msg.prev_seq], msg.data);
				}
				break;
		}
		// Decrypt any encrypted data, store jm_keys for new jm channels >>>

		switch (msg.type) {
			case 'svc_avail':
				this._svc_avail(tcllist.list2array(msg.data));
				break;

			case 'svc_revoke':
				this._svc_revoke(tcllist.list2array(msg.data));
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
				for (key in msg) {
					if (msg.hasOwnProperty(key)) {
						log.error('msg.'+key+': ('+msg[key]+')');
					}
				}
				break;
		}
	},

	_serialize_msg: function(msg) {
		var hdr, sdata, udata;

		hdr = tcllist.array2list([
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
		sdata = tcllist.array2list([
			'1',
			hdr.length,
			udata.length
		]);
		sdata += '\n' + hdr + udata;

		return sdata;
	},

	_send: function(msg) {
		var sdata;

		//console.log('Got request to send msg: ', msg);
		this._set_default_msg_fields(msg);
		sdata = this._serialize_msg(msg);
		this._enqueue(sdata, msg);
	},

	_receive_fragment: function(msgid, is_tail, frag) {
		var complete, so_far;
		//log.debug('_receive_fragment: msgid: ('+msgid+'), is_tail: ('+is_tail+'), frag: ('+frag+')');
		//log.debug('_receive_fragment: msgid: ('+msgid+'), is_tail: ('+is_tail+'), frag length: ('+frag.length+')');
		if (this._defrag_buf[msgid] !== undefined) {
			so_far = this._defrag_buf[msgid];
		} else {
			so_far = '';
		}
		so_far += frag;
		if (is_tail) {
			complete = so_far;
			delete this._defrag_buf[msgid];
			this._receive_msg(Utf8.decode(complete));
		} else {
			this._defrag_buf[msgid] = so_far;
		}
	},

	_receive_raw: function(packet) {
		//packet = Utf8.decode(packet_base64);
		//log.debug('_queue_receive_raw: ('+packet+')');
		var lineend, head, msgid, is_tail, fragment_len, frag, rest;
		rest = packet;
		//log.debug('packet.length: '+packet.length);
		while (rest.length > 0) {
			//log.debug('rest.length: '+rest.length);
			lineend = rest.indexOf("\n");
			if (lineend === -1) {
				throw new Error('corrupt fragment header: '+rest);
			}
			//log.debug('header: '+rest.substr(0, lineend));
			head = tcllist.list2array(rest.substr(0, lineend));
			msgid = Number(head[0]);
			is_tail = Boolean(Number(head[1]));
			fragment_len = Number(head[2]);
			frag = rest.substr(lineend + 1, fragment_len);
			//log.debug('fragment_len: '+fragment_len+', frag.length: '+frag.length);
			if (fragment_len !== frag.length) {
				throw new Error('Fragment length mismatch: expecting '+fragment_len+', got: '+frag.length);
			}
			//rest = rest.substr(lineend + 1 + fragment_len);
			rest = rest.substr(lineend + 1 + fragment_len);
			this._receive_fragment(msgid, is_tail, frag);
		}
	},

	_enqueue: function(sdata, msg) {
		var msgid, payload;
		/* ----- Queueing requires that we get writable notifications -----
		var target, msgid, target_queue;

		target = this.assign(msg);
		msgid = this._msgid_seq++;
		if (this._queues[target] === undefined) {
			target_queue = [];
		} else {
			target_queue = this._queues[target];
		}
		target_queue.push([msgid, sdata]);
		this._queues[target] = target_queue;
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

		evlog.event('m2.queue_msg', tcllist.array2list([
			'to', this.host+':'+this.port,
			'msg', this._evlog_msg(msg)
		]));
	},

	_socket_connected_changed: function(newstate) {
		var e, seq, prev_seq, msg;

		if (newstate) {
			this._send({
				type:	'neighbour_info',
				data:	tcllist.array2list(['type', 'application'])
			});

			try {
				//log.debug('API setting connected to true');
				this._signals.connected.set_state(true);
				this._dispatch_event('connected', true);
			} catch (err) {
				log.error('dispatching connected event went badly: '+err);
			}
		} else {
			log.warning('server closed connection');
			try {
				//log.debug('API setting connected to false');
				this._signalsconnected.set_state(false);
				for (e in this._svc_signals) {
					if (this._svc_signals.hasOwnProperty(e)) {
						this._svc_signals[e].sig.set_state(false);
					}
				}
				// TODO: nack all outstanding requests
				for (seq in this._jm_prev_seq) {
					if (this._jm_prev_seq.hasOwnProperty(seq)) {
						prev_seq = this._jm_prev_seq[seq];

						msg = {
							type:	'jm_can',
							svc:	'sys'
						};
						this._set_default_msg_fields(msg);

						msg.seq = seq;
						msg.prev_seq = tcllist.array2list([prev_seq]);
						this._jm_can(msg);
					}
				}
				this._dispatch_event('connected', false);
			} catch (e2) {
				log.error('dispatching disconnected event went badly: '+e2);
			}
		}
	},

	_dispatch_event: function(event, params) {
		var i, cbs;

		if (this._event_handlers[event]) {
			cbs = this._event_handlers[event];
			for (i=0; i<cbs.length; i++) {
				//log.debug('calling cb '+cbs[i]+',('+params+')');
				cbs[i](params);
			}
		}
	}
});
});



