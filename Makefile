all::
	$(MAKE) -C rootless package FINALPACKAGE=1
	$(MAKE) -C rootful package FINALPACKAGE=1
	$(MAKE) -C jailed

clean::
	$(MAKE) -C rootless clean
	$(MAKE) -C rootful clean
	$(MAKE) -C jailed clean
