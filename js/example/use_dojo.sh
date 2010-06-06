#!/bin/sh

rm dojo || echo -n ""

case "$1" in
	"1.3.2")
		ln -s dojo-release-1.3.2 dojo
	;;

	"1.3")
		ln -s dojo-release-1.3.2 dojo
	;;

	"1.4")
		ln -s ~/pkgs/dojo-release-1.4.0 dojo
	;;

	"1.4s")
		ln -s ~/pkgs/dojo-release-1.4.0-src dojo
	;;

	*)
		echo "Invalid dojo version: \"$1\"" >&2
		exit 1
	;;
esac

exit 0
