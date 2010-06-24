authwebmodule = function(params) { //<<<
	if (typeof params == 'undefined') {
		throw("Must specify svc, api");
	}

	if (typeof params.svc == 'undefined') {
		throw("Must specify svc");
	}

	if (typeof params.api == 'undefined') {
		throw("Must specify api");
	}

	var self;
	self = this;
	this._svc = params.svc;
	this._api = params.api;
	this._name = this._svc.substr(14);

	log.debug("Created authmodule ("+this._name+")");
	this.connector = this._api.connect_svc(this._svc);
	this.connector.signal_ref('authenticated').attach_output(function(newstate) {
		self._authenticated_changed(newstate);
	});
	this.connector.signal_ref('connected').attach_output(function(newstate) {
		log.debug('Authmodule '+self._name+' connector connected: '+newstate);
	});
};

//>>>
authwebmodule.prototype.destroy = function() { //<<<
	log.debug("Cleaning up ("+this._name+")");
	this.connector = this.connector.destroy();
	return null;
};

//>>>
authwebmodule.prototype._authenticated_changed = function(newstate) { //<<<
	var self;
	self = this;
	log.debug('Authmodule '+this._name+' connector authenticated: '+newstate);
	if (newstate) {
		self.connector.req_async('module_info', '', function(msg) {
			log.debug("Got module_info response for ("+self._name+"): "+msg.type);
			log.debug(msg);

			switch (msg.type) {
				case 'ack':
					self._module_info = list2dict(msg.data);
					self.icon = self._module_info.icon;
					self.baseurl = self._module_info.baseurl;
					self.title = self._module_info.title;
					self.name = self._name;
					self.svc = self._svc;
					self.init = self._module_info.init;
					log.debug("Got module_info: ", self._module_info);
					self.gotInfo();
					break;

				case 'nack':
					throw("module_info request for ("+self._name+") denied: "+msg.data);

				default:
					throw("Got unexpected response to module_info request for ("+self._name+"): "+msg.type);
			}
		});
	} else {
	}
};

//>>>
authwebmodule.prototype.gotInfo = function() { //<<<
	log.debug("Got info for ("+this._name+")");
};

//>>>
authwebmodule.prototype.http_get = function(page, cb) { //<<<
	this.connector.req_async('http_get', serialize_tcl_list([this.page]), cb);
};

//>>>

// vim: ft=javascript foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
