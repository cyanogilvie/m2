webmodule = function(params) { //<<<
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
	this._name = this._svc.substr(10);

	log.debug("Created ("+this._name+")");

	this._api.req(this._svc, serialize_tcl_list(['module_info']), function(msg) {
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
};

//>>>
webmodule.prototype.destroy = function() { //<<<
	log.debug("Cleaning up ("+this._name+")");
	return null;
};

//>>>
webmodule.prototype.gotInfo = function() { //<<<
	log.debug("Got info for ("+this._name+")");
};

//>>>
webmodule.prototype.http_get = function(page, cb) { //<<<
	this._api.req(this.svc, serialize_tcl_list(['http_get', this.page]), cb);
};

//>>>

// vim: ft=javascript foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
