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
	use Net::IPv4Addr;
	use XML::XPath;

You need a .rtrc file in your home directory, containing your credentials.
For example:

	username freddie
	password flintstone
	hostname rt.yourorg.ca

You can use any format that Config::General understands, but this is a format that's shared with the venerable rt.pl script.

This file must be mode 0400 or 0600, else the config file parser will bomb out. This is afeaturenotabug.

I do not intend to support the use of environment variables to set the RT credentials, as per rt.pl. I believe this is dangerous. However, all scripts support a -f option, the argument of which must be a path to a configuration file. The ownership and permissions are still checked on this file.

License
-------

BSD-new.

Authors
-------

Mike Patterson, Waterloo IST ISS <mike.patterson@uwaterloo.ca>
Cheng Jie Shi, Winter 2013 IST ISS Co-Op <cjshi@uwaterloo.ca>
