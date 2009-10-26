console.log('webmodule foo, cleanup, this is: ', this);
if (typeof this.store != 'undefined') {
	this.store.destroy();
	this.store = null;
}
