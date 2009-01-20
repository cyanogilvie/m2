#!/bin/sh

export GIT_DIR=/home/cyan/git/m2/.git

RPMVER=$(grep '^Version:' SPECS/m2_node.spec | awk '{print $2}')
echo "RPMVER: ($RPMVER)"

git-archive --format=tar --prefix=m2_node-$RPMVER/ $RPMVER | gzip > SOURCES/m2_node-$RPMVER.tar.gz

rpmbuild -ba SPECS/m2_node.spec
#cp RPMS/i386/
