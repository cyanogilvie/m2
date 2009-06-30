dojo.provide('sitelocal.ModuleLauncher');

dojo.require('dijit._Widget');
dojo.require('dijit._Templated');

dojo.declare('sitelocal.ModuleLauncher', [dijit._Widget, dijit._Templated], {
	templatePath: dojo.moduleUrl('sitelocal', 'templates/ModuleLauncher.html'),
	modulename: '',
	icon: '',
	label: '',
	svc: '',

	postCreate: function() {
		console.log('foo');
		this.inherited(arguments);
		console.log('bar');
	},

	startup: function() {
		// Children are available now
		this.inherited(arguments);
		console.log('baz');
	},

	onClick: function(ev) {
		console.log('default onClick '+this.label);
	},

	_onClick: function(ev) {
		console.log('hello '+this.label);
	},

	_mouseOver: function(ev) {
		if (ev.target == this.domNode) {
			console.log('mouseover '+this.label);
		}
		console.log(ev);
	},

	_cancelMouseOver: function(ev) {
		ev.stopPropagation();
		console.log('_cancelMouseOver');
		if (ev.target == this.domNode) {
			console.log('mouseover '+this.label);
		}
		console.log(ev);
	},

	_mouseOut: function(ev) {
		if (ev.target == this.domNode) {
			console.log('_mouseOut '+this.label);
		}
		console.log(ev);
	}
});
