#!/usr/bin/env perl
use strict;
use warnings;

# Print out full details on a given RT number

use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;
use Config::General;
use RT::Client::REST;
use Error qw|:try|;
use Date::Manip;
use ConConn;

my $ticket;
my %config = ISSRT::ConConn::GetConfig();

my $rt = RT::Client::REST->new(
	server => 'https://' . $config{hostname},
	timeout => 30,
);

try {
	$rt->login(username => $config{username}, password => $config{password});
} catch Exception::Class::Base with {
	die "problem logging in: ", shift->message;
};

die "No search string given\n" unless $ARGV[0];

try {
	$ticket = $rt->show(type => 'ticket', id => $ARGV[0]);
} catch RT::Client::REST::UnauthorizedActionException with {
    print "You are not authorized to view ticket $ARGV[0]\n";
} catch RT::Client::REST::Exception with {
	print "DERP\n";
};

print Dumper($ticket);
