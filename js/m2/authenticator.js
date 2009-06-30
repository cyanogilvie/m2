

m2.authenticator = new m2.api;
m2.authenticator.constructor = m2.authenticator;

m2.authenticator = function(params) { //<<<
	// Public
	this.pbkey = 'authenticator.pub';
	this.profile_cb = null;

	if (typeof params != 'undefined') {
		if (typeof params.host != 'undefined') {
			this.host = params.host;
		}
		if (typeof params.port != 'undefined') {
			this.port = params.port;
		}
		if (typeof params.log != 'undefined') {
			this.log = params.log;
		}

		if (typeof params.pbkey != 'undefined') {
			this.pbkey = params.pbkey;
		}
		if (typeof params.profile_cb != 'undefined') {
			this.profile_cb = params.profile_cb;
		}
	}

	// Private
	var self;
	self = this;
	this._signals = new Hash;
	this._signals.setItem('available', new Signal({name: 'available'}));
	this._signals.setItem('established', new Signal({name: 'established'}));
	this._signals.setItem('authenticator', new Signal({name: 'authenticator'}));
	this._signals.setItem('login_pending', new Gate({name: 'login_pending', mode: 'and'}));
	this._signals.setItem('got_perms', new Signal({name: 'got_perms'}));
	this._signals.setItem('got_attribs', new Signal({name: 'got_attribs'}));
	this._signals.setItem('got_prefs', new Signal({name: 'got_prefs'}));

	this._signals.getItem('login_allowed').attach_input(
		this._signals.getItem('login_pending'), 'inverted'
	);
	this._signals.getItem('login_allowed').attach_input(
		this._signals.getItem('authenticated'), 'inverted'
	);
	this._signals.getItem('login_allowed').attach_input(
		this._signals.getItem('established')
	);

	this._fetch_pbkey();
};

//>>>

m2.authenticator.prototype._fetch_pbkey = function() { //<<<
	// TODO: sync xhr request for pbkey
};

//>>>

// vim: ft=js foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
