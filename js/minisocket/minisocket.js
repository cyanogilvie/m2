function jsSocket(args) {
	if (this instanceof arguments.callee) {
		if (typeof this.init == 'function') {
			this.init.apply(this, (args && args.callee) ? args : arguments);
		}
	} else {
		return new arguments.callee(arguments);
	}
}

jsSocket.swf = 'jsSocket.swf';
jsSocket.sockets = {};
jsSocket.callback = function(id, type, data) {
	var sock;
	sock = jsSocket.sockets[id];

	setTimeout(function(){
		sock.callback.call(sock, type, data);
	}, 0);
};

jsSocket.prototype = {
	id: null,
	num: null,
	host: null,
	port: null,

	init: function(opts) {
		var self;
		self = this;

		if (opts.host) {
			this.host = opts.host;
		}
		if (this.host === null) {
			this.host = window.location.hostname;
		}
		if (opts.port) {
			this.port = opts.port;
		}
		if (opts.autoconnect) {
			this.autoconnect = opts.autoconnect;
		}
		if (opts.autoreconnect) {
			this.autoreconnect = opts.autoreconnect;
		}

		if (!this.num) {
			if (!jsSocket.id) {
				jsSocket.id = 1;
			}
			this.num = jsSocket.id++;
			this.id = 'jsSocket_' + this.num;
		}

		this.signals = {};
		this.signals.loaded = new Signal({name: 'loaded'});
		this.signals.connected = new Signal({name: 'connected'});

		jsSocket.sockets[self.id] = self;

		dojo.addOnLoad(function(){
			self._onload();
		});
		dojo.addOnUnload(function() {
			self.close();
		});
	},

	_onload: function() {
		var flashnode, embednode;

		flashnode = document.createElement('div');
		flashnode.setAttribute('id', 'jsSocketWrapper_' + this.num);
		flashnode.setAttribute('style', 'background-color: rgb(255, 255, 255); width: 1px;');

		embednode = document.createElement('embed');
		embednode.setAttribute('id', this.id);
		embednode.setAttribute('width', '1');
		embednode.setAttribute('height', '1');
		embednode.setAttribute('flashvars', 'id='+this.id+'&\nsizedReads=false');
		embednode.setAttribute('autoplay', 'false');
		embednode.setAttribute('wmode', 'transparent');
		embednode.setAttribute('bgcolor', '#ffffff');
		embednode.setAttribute('src', jsSocket.swf);
		embednode.setAttribute('style', 'display: block;');
		flashnode.appendChild(embednode);

		document.body.appendChild(flashnode);
	},

	autoconnect: true,
	autoreconnect: true,

	reconnect: function() {
		var secs, self;

		secs = 0;
		self = this;

		//log.debug('reconnecting');
		if (this.reconnect_interval) {
			clearInterval(this.reconnect_interval);

			this.reconnect_countdown = this.reconnect_countdown * 2;

			if (this.reconnect_countdown > 48) {
				this.reconnect_countdown = 48;
			}
			//log.debug('will reconnect in ' + this.reconnect_countdown);
		}

		this.reconnect_interval = setInterval(function() {
			var remain;

			remain = self.reconnect_countdown - ++secs;
			if (remain === 0) {
				//log.debug('reconnecting now...');
				clearInterval(self.reconnect_interval);

				self.autoconnect = true;
				self.open();
			} else {
				//log.debug('reconnecting in '+remain);
			}
		}, 1000);
	},
	reconnect_interval: null,
	reconnect_countdown: 3,

	open: function(host, port) {
		if (typeof host != 'undefined') {
			this.host = host;
		}
		if (typeof port != 'undefined') {
			this.port = port;
		}
		this.host = this.host || window.location.hostname;
		if (typeof this.port == 'undefined' || this.port === null) {
			throw('error: no port specified');
		}
		return this.sock.open(this.host, this.port);
	},

	send: function(data) {
		return this.sock.send(Base64.encode(data));
	},

	close: function() {
		this.autoreconnect = true;
		if (this.signals.loaded.state() && this.signals.connected.state()) {
			this.sock.close();
		}
	},

	callback: function(type, data) {
		switch (type) {
			case 'onLoaded':
				//log.debug('loaded');
				this.signals.loaded.set_state(true);
				this.sock = document.getElementById(this.id);
				if (this.autoconnect) {
					this.open();
				}
				break;

			case 'onOpen':
				if (data === true) {
					//log.debug('connected');
					this.reconnect_countdown = 3;
					if (this.reconnect_interval) {
						clearInterval(this.reconnect_interval);
					}
					this.signals.connected.set_state(true);
				} else {
					//log.debug('connect failed');
					if (this.autoreconnect) {
						this.reconnect();
					}
				}
				break;

			case 'onClose':
				//log.debug('disconnected');
				this.signals.connected.set_state(false);
				if (this.autoreconnect) {
					this.reconnect();
				}
				break;

			case 'onData':
				this.received(Base64.decode(data));
				break;
		}
	},

	received: function(){}
};
