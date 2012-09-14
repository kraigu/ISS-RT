#!/usr/bin/env perl
use strict;
use warnings;

# Search an RTIR *Incident* queue for a given string in a description
# Mike Patterson <mike.patterson@uwaterloo.ca>
# in his guise as IST-ISS staff member, August 2012

use Data::Dumper;
use Config::General;
use RT::Client::REST;
use Error qw|:try|;
use Date::Manip;

my $debug = 0; # 3 or greater prints passwords, watch out

my $configfile = qq|$ENV{"HOME"}/.rtrc|;

my ($ticket,$checkmonth);
my (%classifications,%constituencies);

if( ! -e $configfile){ 
        die "\n$configfile does not exist\n";
}
my $perms = sprintf("%o",(stat($configfile))[2] & 07777);
if($debug > 3){ print "Permissions on rc file: " . Dumper($perms); }
die "\nConfig file must not have any more than owner rw\n"
        unless ($perms == '600' || $perms == '0400');

my $conf = new Config::General($configfile);
my %config = $conf->getall;
if($debug > 3){ print Dumper(\%config); }

die "\nNo password!\n" unless $config{password};
die "\nNo hostname!\n" unless $config{hostname};
die "\nNo username!\n" unless $config{username};

my $rt = RT::Client::REST->new(
	server => 'https://' . $config{hostname},
	timeout => 30,
);

try {
	$rt->login(username => $config{username}, password => $config{password});
} catch Exception::Class::Base with {
	die "problem logging in: ", shift->message;
};

my $searchstr = $ARGV[0] || die "No search string given\n";

my $qstring = qq|
Queue = 'Incidents'
AND 'CF.{_RTIR_Description}' LIKE '%$searchstr%'
|;
if($debug > 0){ print "Query string\n$qstring\n"; }

my @ids = $rt->search(
	type => 'ticket',
	query => $qstring
);

if($debug > 0){	print scalar @ids . " incidents\n"; }
if($debug > 1){	print Dumper(@ids); }

# Going to want: id, Subject, RTIR_IP, RTIR_State, Classification
for my $id (@ids) {
	# show() returns a hash reference
	my ($ticket) = $rt->show(type=>'ticket',id=>$id);
	#print Dumper($ticket);
	my $subj = $ticket->{'Subject'};
	my $desc = $ticket->{'CF.{_RTIR_Description}'};
	print "ID: $id\tSubject: $subj\tDescription: $desc\n\n";
}
