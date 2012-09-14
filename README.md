ISS-RT
======

Some tools I wrote to talk to RT and to do reporting.

Modularisation and style comments (and patches!) welcome.

What's here is functional but ugly. I aim to fix the latter eventually.

Requirements
------------

	use Config::General;
	use RT::Client::REST;
	use Error qw|:try|;
	use Date::Manip;

You need a .rtrc file in your home directory, containing your credentials.
For example:

	username=freddie
	password=flintstone
	hostname=rt.yourorg.ca

License
-------

BSD-new.
