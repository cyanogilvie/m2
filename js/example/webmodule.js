webmodule = function(params) { //<<<
	if (typeof window != 'undefined' && typeof window.console != 'undefined') {
		this.log = console.log;
	} else {
		if (typeof dump != 'undefined') {
			this.log = function(msg) {
				print(msg);
			};
		} else if (typeof print != 'undefined') {
			this.log = function(msg) {
				dump(msg+"\n");
			};
		} else {
			this.log = function(msg) {};
		}
	}

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

	this.log("Created ("+this._name+")");

	this._api.req(this._svc, serialize_tcl_list(['module_info']), function(msg) {
		self.log("Got module_info response for ("+self._name+"): "+msg.type);
		self.log(msg);

		switch (msg.type) {
			case 'ack':
				self._module_info = list2dict(msg.data);
				self.icon = self._module_info.icon;
				self.baseurl = self._module_info.baseurl;
				self.title = self._module_info.title;
				self.page = self._module_info.page;
				self.name = self._name;
				self.svc = self._svc;
				self.init = self._module_info.init;
				self.cleanup = self._module_info.cleanup;
				console.log("Got module_info: ", self._module_info);
				self.gotInfo();
				break;

			case 'nack':
				throw("module_info request for ("+self._name+") denied: "+msg.data);
				break;

			default:
				throw("Got unexpected response to module_info request for ("+self._name+"): "+msg.type);
				break;
		}
	});
}

//>>>
webmodule.prototype.destroy = function() { //<<<
	this.log("Cleaning up ("+this._name+")");
	return null;
};

//>>>
webmodule.prototype.gotInfo = function() { //<<<
	this.log("Got info for ("+this._name+")");
};

//>>>

// vim: ft=javascript foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4
