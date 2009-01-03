VER=0.20

BASESCRIPTS = \
			  init.tcl \
			  scripts/api.itcl \
			  scripts/api2.itcl \
			  scripts/chans.itcl \
			  scripts/refcounted.tcl \
			  scripts/msg.tcl \
			  scripts/node.tcl \
			  scripts/port.itcl

all: tm

tm: scripts/*.itcl scripts/*.tcl init.tcl
	-rm -rf tm
	install -d tm
	cat $(BASESCRIPTS) > tm/m2-$(VER).tm

install: all
	./install

clean:
	-rm -rf tm
