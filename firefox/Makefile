DESTDIR=

all: xpi

xpi:
	(cd m2; zip -r ../m2-0.20.0.zip .)
	mv m2-0.20.0.zip m2-0.20.0.xpi

clean:
	-rm *.zip *.xpi

