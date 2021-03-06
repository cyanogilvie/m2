#!/bin/sh

export GIT_DIR=/home/cyan/git/m2/.git

RPMVER=$(grep '^Version:' SPECS/m2_node.spec | awk '{print $2}')
echo "RPMVER: ($RPMVER)"

git archive --format=tar --prefix=m2_node-$RPMVER/ $RPMVER | gzip > SOURCES/m2_node-$RPMVER.tar.gz

rpmbuild --target i386-gnu-linux -ba SPECS/m2_node.spec
cp RPMS/i386/m2_node-$RPMVER-1.i386.rpm /home/cyan/git/m2/out
