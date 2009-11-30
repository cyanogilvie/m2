m2.connector = function(a_auth, a_svc) { //<<<<
	this.auth = a_auth;
	this.svc = a_svc;

	this.pbkey = null;

	var self = this;
	this.signals = {};
	this.signals.available = this.auth.svc_signal(svc);
	this.signals.connected = new Signal({name: svc+' connected'});
	this.signals.authenticated = new Signal({name: svc+' authenticated'});
	this.signals.got_svc_pbkey = new Signal({name: svc+' got_svc_pbkey'});
	this.signals.connect_ready = new Gate({name: svc+' connect_ready', mode: 'and'});
	// TODO: need_reconnect domino

	this.signals.connect_ready.attach_input(this.auth.signal_ref('authenticated'));
	this.signals.connect_ready.attach_input(this.signals.got_svc_pbkey);
	this.signals.connect_ready.attach_input(this.signals.available);

	this.auth.signal_ref('authenticated').attach_output(function(newstate) {
		self._authenticated_changed(newstate);
	});
	// TODO: attach need_reconnect domino to run _reconnect
	this.signals.connect_ready.attach_output(function(newstate){
		self._connect_ready_changed(newstate);
	});
};

//>>>>
m2.connector.prototype.destroy = function() { //<<<<
	// TODO: the stuff that goes here
	return null;
};

//>>>>

m2.connector.prototype._connect_ready_changed = function(newstate) { //<<<<
	if (newstate) {
		this.log('setting reconnect in motion');
		this.dominos.need_reconnect.tip();
	}
};

//>>>>
m2.connector.prototype._authenticated_changed = function(newstate) { //<<<<
	var self;

	if (newstate) {
		this.log('requesting public key for ('+this.svc+') ...')
		self = this;
		this.auth.get_svc_pbkey(this.svc, function(ok, data) {
			if (ok) {
				self.pbkey_asc = data;
				self.log('got public key ascii format for ('+this.svc+'), loading into key ...');
				try {
					self.pbkey = cfcrypto.rsa.load_asn1_pubkey_from_value(self.pbkey_asc);
					self.log('got public key for ('+self.svc+')');
					self.got_svc_pbkey.set_state(true);
				} catch(e) {
					self.log('error decoding public key for ('+self.svc+'): '+e);
				}
			} else {
				self.log('error fetching public key for ('+self.svc+'): '+data);
			}
		});
	} else {
		this.signals.got_svc_pbkey.set_state(false);
		if (this.pbkey !== null) {
			this.pbkey = null;
		}
	}
};

//>>>>

// vim: ft=javascript foldmethod=marker foldmarker=<<<<,>>>> ts=4 shiftwidth=4
