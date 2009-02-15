DESTDIR=

all: tm m2_node

tm:
	tbuild build m2

m2_node: tm m2_node.tcl
	tbuild build m2_node

install-tm: tm
	tbuild install m2

install: install-tm
	tbuild install m2_node

install-rpm: all
	install -d $(DESTDIR)/usr/bin
	install -d $(DESTDIR)/etc/init.d
	install -d $(DESTDIR)/etc/sysconfig
	install --mode 0755 m2_node $(DESTDIR)/usr/bin
	install --mode 0644 sysv/config $(DESTDIR)/etc/sysconfig/m2_node
	install --mode 0755 sysv/m2_node $(DESTDIR)/etc/init.d

clean:
	-rm -rf tm bin
