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

all: tm m2_node m2_node.bin

tm: scripts/*.tcl init.tcl
	-rm -rf tm
	install -d tm
	cat $(BASESCRIPTS) > tm/m2-$(VER).tm

m2_node: tm m2_node.vfs/m2_node
	rsync -a tm m2_node.vfs
	sdx wrap m2_node -interp kbskit8.6

m2_node.bin: m2_node.vfs/m2_node
	sdx wrap m2_node.bin -vfs m2_node.vfs -runtime kbskit8.6-cli

install: all
	./install

clean:
	-rm -rf tm m2_node m2_node.bin 
