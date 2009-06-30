dojo.provide('sitelocal.dschanStore');
dojo.require('dojo.data.api.Read');

dojo.declare('sitelocal.dschanStore', ['dojo.data.api.Read'], {
	m2: null,
	tickertape_avail: null,
	svc: null,
	reqdata: null,
	_items: null,

	constructor: function(properties) {
		console.log('Constructing sitelocal.dschanStore', properties);
		this._items = new Hash;
		this.m2 = properties.m2;
		this.svc = properties.svc;
		this.reqdata = properties.reqdata;
		this.tickertape_avail = this.m2.svc_signal(this.svc);
		this.tickertape_avail.attach_output(dojo.hitch(this, this._tickertape_avail_changed));
	},

	disconnect: function() {
		console.log('in dschanStore disconnect');
		if (this._jm_seq !== null && this._jm_prev_seq !== null) {
			this.m2.jm_disconnect(this._jm_seq, this._jm_prev_seq);
			this._jm_seq = null;
			this._jm_prev_seq = null;
		}
	},

	_tickertape_avail_changed: function(newstate) {
		console.log('_tickertape_avail_changed: ('+newstate+')');
		if (newstate) {
			this.m2.req(this.svc, this.reqdata, dojo.hitch(this, this._dschan_response));
		} else {
		}
	},

	_jm_seq: null,
	_jm_prev_seq: null,
	_dschan_response: function(msg) {
		var details;

		console.log('_dschan_response: msg: ', msg);
		switch (msg.type) {
			case 'ack':
				break;

			case 'nack':
				break;

			case 'pr_jm':
				details = parse_tcl_list(msg.data);
				switch (details[0]) {
					case 'init':
						this._jm_seq = msg.seq;
						this._jm_prev_seq = msg.prev_seq;
						this._init_messages(details[1]);
						break;

					default:
						console.log('Bad pr_jm op: ('+details[0]+')');
						break;
				}
				break;

			case 'jm':
				console.log('jm: '+msg.data);
				details = parse_tcl_list(msg.data);
				switch (details[0]) {
					case 'new':
						this._new_message(details[1]);
						break;

					case 'removed':
						this._removed_message(details[1]);
						break;

					default:
						console.log('Bad jm op: ('+details[0]+')');
						break;
				}
				break;

			case 'jm_can':
				console.log('jm_can');
				if (msg.seq == this._jm_seq) {
					this._jm_seq = null;
					this._jm_prev_seq = null;
					this._disconnected();
				}
				break;

			default:
				console.log('Unexpected response type: ('+msg.type+')');
				break;
		}
	},

	_init_messages: function(data) {
		var messages, i, message, details, fqid, idinfo, lineend, summary, body, newitem;
		messages = parse_tcl_list(data);

		for (i=0; i<messages.length; i++) {
			message = parse_tcl_list(messages[i]);
			idinfo = parse_tcl_list(message[0]);
			fqid = this._make_fqid(idinfo[0], idinfo[1], idinfo[2]);
			details = list2dict(message[1]);
			lineend = details.message.indexOf("\n");
			if (lineend == -1) {
				console.log('lineend: '+lineend+', msg: ('+details.message+')');
				summary = details.message;
				body = '';
			} else {
				summary = details.message.substr(0, lineend);
				body = details.message.substr(lineend+1);
			}
			console.log('message, id: ('+fqid+'), time: ('+details.time+'), summary: ('+summary+'), body: ('+body+')');
			newitem = {
				id: fqid,
				time: details.time,
				summary: summary,
				body: body
			};
			this._items.setItem(fqid, newitem);

			this.onNew(fqid);
		}
	},

	_make_fqid: function(scope, details, id) {
		switch (scope) {
			case 'global':
				fqid = 'global/'+id;
				break;

			case 'branch':
				fqid = 'branches/'+details+'/'+id;
				break;

			case 'region':
				fqid = 'regions/'+details+'/'+id;
				break;

			default:
				console.log('scope ('+scope+') not handled');
				break;
		}
		return fqid;
	},

	_new_message: function(data) {
		var details, scope, fqid, lineend, summary, body, changes, newitem, old, keys, i;

		details = list2dict(data);
		console.log('_new_message: ', details);

		details = list2dict(data);
		scope = parse_tcl_list(details.scope);
		fqid = this._make_fqid(scope[0], scope[1], details.id);
		lineend = details.message.indexOf("\n");
		if (lineend == -1) {
			console.log('lineend: '+lineend+', msg: ('+details.message+')');
			summary = details.message;
			body = '';
		} else {
			summary = details.message.substr(0, lineend);
			body = details.message.substr(lineend+1);
		}

		newitem = {
			id: fqid,
			time: details.time,
			summary: summary,
			body: body
		};
		if (this._items.hasItem(fqid)) {
			old = this._items.getItem(fqid);
			changes = new Hash;
			if (newitem.id !== old.id) {
				changes.setItem('id', {
					oldValue: old.id,
					newValue: newitem.id
				});
			}
			if (newitem.time !== old.time) {
				changes.setItem('time', {
					oldValue: old.time,
					newValue: newitem.time
				});
			}
			if (newitem.summary !== old.summary) {
				changes.setItem('summary', {
					oldValue: old.summary,
					newValue: newitem.summary
				});
			}
			if (newitem.body !== old.body) {
				changes.setItem('body', {
					oldValue: old.body,
					newValue: newitem.body
				});
			}
		}
		this._items.setItem(fqid, newitem);
		if (typeof changes == 'undefined') {
			this.onNew(fqid);
		} else {
			keys = changes.keys();
			for (i=0; i<keys.length; i++) {
				this.onSet(fqid, keys[i],
						changes.getItem(keys[i]).oldValue,
						changes.getItem(keys[i]).newValue);
			}
		}
	},

	_removed_message: function(data) {
		var details, scope, fqid;

		details = list2dict(data);
		scope = parse_tcl_list(details.scope);
		fqid = this._make_fqid(scope[0], scope[1], details.id);
		console.log('_removed_message: ', details);
		this.onDelete(fqid);
		this._items.removeItem(fqid);
	},

	_disconnected: function() {
		var keys, i;

		keys = this._items.keys();

		for (i=0; i<keys.length; i++) {
			this.onDelete(keys[i]);
			this._items.removeItem(keys[i]);
		}
	},

	getValue: function(id, attribute, defaultValue) {
		var item;
		item = this._items.getItem(id);
		if (item[attribute]) {
			return item[attribute];
		} else {
			return defaultValue;
		}
		// returns scalar
	},

	getValues: function(item, attribute) {
		console.debug('sitelocal.dschanStore.getValues');
		// returns array
	},

	getAttributes: function(item) {
		console.debug('sitelocal.dschanStore.getAttributes');
		// returns array
	},

	hasAttribute: function(item, attribute) {
		console.debug('sitelocal.dschanStore.hasAttribute');
		// returns boolean
	},

	containsValue: function(item, attribute, value) {
		console.debug('sitelocal.dschanStore.containsValue');
		// returns boolean
	},

	isItem: function(something) {
		return this._items.hasItem(something);
	},

	isItemLoaded: function(something) {
		return this._items.hasItem(something);
	},

	loadItem: function(keywordArgs) {
		console.debug('sitelocal.dschanStore.loadItem');
		// keywordArgs looks like this:
		// {
		//		item: object,
		//		onItem: function(item),
		//		onError: function(error),
		//		scope: object
		// }
	},

	fetch: function(keywordArgs) {
		var ids, i, size, start, these, scope;

		try {
			console.debug('sitelocal.dschanStore.fetch:', keywordArgs);
			// keywordArgs may contain:
			// {
			//		query: query-object or query-string,
			//		queryOptions: object,
			//		onBegin: Function,
			//		onItem: Function,
			//		onComplete: Function,
			//		onError: Function,
			//		scope: object,
			//		start: int
			//		count: int
			//		sort: array
			// }

			// returns object conforming to dojo.data.api.Request API
			keywordArgs.abort = function() {
				// we're not doing anything anyway
			};

			these = null;
			ids = this._items.keys();
			size = ids.length;
			scope = keywordArgs.scope || dojo.global;

			if (!keywordArgs.store) {
				keywordArgs.store = this;
			}

			start = keywordArgs.query.start ? keywordArgs.start : 0;

			if (keywordArgs.query.count) {
				if (size + start > keywordArgs.query.count) {
					size = keywordArgs.query.count - start;
				}
			}

			if (keywordArgs.onBegin) {
				keywordArgs.onBegin.call(scope, size, keywordArgs);
			}
			if (keywordArgs.onItem) {
				these = [];
				for (i=start; i<start+size; i++) {
					these.push(ids[i]);
					keywordArgs.onItem.call(scope, ids[i], keywordArgs);
				}
			}
			if (keywordArgs.onComplete) {
				keywordArgs.onComplete.call(scope, these, keywordArgs);
			}
		} catch(e) {
			console.log('Error: "'+e+'"');
		}

		return keywordArgs;
	},

	getFeatures: function() {
		//console.debug('sitelocal.dschanStore.getFeatures');
		return {
			'dojo.data.api.Read': true,
			'dojo.data.api.Notification': true
		};
	},

	close: function(request) {
		console.debug('sitelocal.dschanStore.close');
		// request is an object returned from our fetch method
	},

	getLabel: function(item) {
		console.debug('sitelocal.dschanStore.getLabel');
		// returns string
	},

	getLabelAttributes: function(item) {
		console.debug('sitelocal.dschanStore.getLabelAttributes');
		// returns attributes of item that are contained in it's label string
	},

	onSet: function(item, attribute, oldValue, newValue) {
		console.log('onSet: item: ('+item+')[\''+attribute+'\']: "'+oldValue+'" -> "'+newValue+'"');
	},

	onNew: function(newItem, parentInfo) {
	},

	onDelete: function(deletedItem) {
	}
});
