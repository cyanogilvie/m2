dojo.provide('sitelocal.ModuleLauncherTest');

dojo.require('dijit._Widget');
dojo.require('dijit._Templated');

dojo.declare('sitelocal.ModuleLauncherTest', [dijit._Widget, dijit._Templated], {
	templatePath: dojo.moduleUrl('sitelocal', 'templates/ModuleLauncherTest.html'),
	modulename: '',
	icon: '',
	label: '',
	svc: '',
	page: '',
	pageurl: '',
	baseurl: '',
	init: '',
	cleanup: '',

	pagedijit: null,

	postCreate: function() {
		console.log('ml foo');
		this.inherited(arguments);
		console.log('ml bar, modulename: '+this.modulename+' icon: '+this.icon);
		console.log('Attempting to run init js:\n'+this.init);
		try {
			eval(this.init);
		} catch(e) {
			console.err('Error in webmodule init script for '+this.svc+': '+e);
			return;
		}
		console.log('Init javascript loaded for '+this.svc);
	},

	destroyRecursive: function() {
		if (this.pagedijit != null) {

			dijit.byId('tabs').removeChild(this.pagedijit);
			this.pagedijit.destroyRecursive();
			this.pagedijit = null;
		}
		if (typeof this.cleanup != 'undefined') {
			console.log("Webmodule "+this.svc+" running cleanup script");
			try {
				eval(this.cleanup);
			} catch(e) {
				console.error("Webmodule "+this.svc+" error in cleanup script: "+e);
			}
			delete this.cleanup;
		} else {
			console.log("Webmodule "+this.svc+" no cleanup script stored");
		}
		this.inherited(arguments);
	},

	_onClick: function() {
		console.log('Got click for '+this.modulename);
		this._openModule();
	},

	_openModule: function() {
		if (this.pageurl === '') return;

		console.log('_openModule foo');
		this.pagedijit = new dijit.layout.ContentPane({
			title: this.label,
			closable: true
		});
		dijit.byId('tabs').addChild(this.pagedijit);
		console.log('_openModule bar');
		console.log('Requesting this.svc: ('+this.svc+'), ('+serialize_tcl_list(['http_get', this.pagedijit])+')');
		api.req(this.svc, serialize_tcl_list(['http_get', this.page]), dojo.hitch(this, function(msg) {
			console.log('got http_get response: '+msg.type);
			var resp_parts;

			switch (msg.type) {
				case 'ack':
					resp_parts = parse_tcl_list(msg.data);
					console.log('Got http_get response, encoding: ('+resp_parts[1]+'), mimetype: ('+resp_parts[2]+')');
					this.pagedijit.attr('content', resp_parts[0]);
					dijit.byId('tabs').selectChild(this.pagedijit);
					break;

				case 'nack':
					this.pagedijit._onError('Download', msg.data, 'Error fetching "'+this.pagedijit+'": '+msg.data);
					dijit.byId('tabs').selectChild(this.pagedijit);
					break;

				default:
					throw('Unexpected response to http_get request: "'+msg.type+'"');
			}
		}));
		console.log('_openModule baz');
	}
});
