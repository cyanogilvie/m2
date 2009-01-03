VER=0.20

BASESCRIPTS = \
			  init.tcl \
			  scripts/intersect3.tcl \
			  scripts/refcounted.tcl \
			  scripts/msg.tcl \
			  scripts/node.tcl \
			  scripts/handlers.tcl \
			  scripts/baselog.tcl \
			  scripts/port.tcl
#			  scripts/api.itcl \
			  scripts/api2.itcl \

all: tm

tm: scripts/*.itcl scripts/*.tcl init.tcl
	-rm -rf tm
	install -d tm
	cat $(BASESCRIPTS) > tm/m2-$(VER).tm

install: all
	./install

clean:
	-rm -rf tm
