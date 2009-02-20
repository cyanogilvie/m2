DESTDIR=

all: xpi

xpi:
	(cd example/; zip -r ../m2_example-0.20.0.zip .)
	mv m2_example-0.20.0.zip m2_example-0.20.0.xpi
	(cd m2; zip -r ../m2-0.20.0.zip .)
	mv m2-0.20.0.zip m2-0.20.0.xpi

clean:
	-rm *.zip *.xpi

