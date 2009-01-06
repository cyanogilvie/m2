VER=0.20

BASESCRIPTS = \
			  init.tcl \
			  scripts/intersect3.tcl \
			  scripts/pclass.tcl \
			  scripts/handlers.tcl \
			  scripts/baselog.tcl \
			  scripts/signalsource.tcl \
			  scripts/signal.tcl \
			  scripts/gate.tcl \
			  scripts/domino.tcl \
			  scripts/refcounted.tcl \
			  scripts/msg.tcl \
			  scripts/node.tcl \
			  scripts/port.tcl \
			  scripts/api.tcl \
			  scripts/api2.tcl

all: tm

tm: scripts/*.tcl init.tcl
	-rm -rf tm
	install -d tm
	cat $(BASESCRIPTS) > tm/m2-$(VER).tm

install: all
	./install

clean:
	-rm -rf tm
