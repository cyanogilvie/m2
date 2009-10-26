dojo.require('dijit.form.Button');
dojo.require('dijit.layout.BorderContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require('dojox.grid.DataGrid');
dojo.require('dojox.grid.compat._grid.publicEvents');
dojo.require('sitelocal.dschanStore');

console.log('webmodule foo, this is: ', this);
this.store = new sitelocal.dschanStore({
	svc: this.svc,
	m2: api,
	reqdata: serialize_tcl_list(['store_dschan'])
});
