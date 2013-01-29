#!/usr/bin/env perl
use strict;
use warnings;

# Search an RTIR Incidents and Investigations queues for a given IP address
# in the IP custom field.
# Mike Patterson <mike.patterson@uwaterloo.ca>
# in his guise as IST-ISS staff member, Feb 2012
# added Investigations May 2012
# more complete output (dates) Oct 2012

use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;
use Config::General;
use RT::Client::REST;
use Error qw|:try|;
use Date::Manip;
use ConConn;

my $debug = 0;

my ($ticket,$checkmonth);
my (%classifications,%constituencies);

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

my $ipsearch = $ARGV[0] || die "No IP\n";

my $qstring = qq|
(Queue = 'Incidents' OR Queue = 'Investigations')
AND CF.{_RTIR_IP} = '$ipsearch'
|;
if($debug > 0){ print "Query string\n$qstring\n"; }

my @ids = $rt->search(
	type => 'ticket',
	query => $qstring
);

if($debug > 0){	print scalar @ids . " incidents\n"; }
if($debug > 1){	print Dumper(@ids); }

for my $id (@ids) {
	# show() returns a hash reference
	my ($ticket) = $rt->show(type=>'ticket',id=>$id);
	if($debug > 0) {
		print Dumper($ticket);
	}
	my $class = $ticket->{'CF.{_RTIR_Classification}'} || 'none';
	my $ipl = $ticket->{'CF.{_RTIR_IP}'};
	my $subj = $ticket->{'Subject'};
	my $state = $ticket->{'CF.{_RTIR_State}'};
	my $queue = $ticket->{'Queue'};
	my $cdate = $ticket->{'Created'};
	my $rdate = $ticket->{'Resolved'} || '';
	my $rreason = $ticket->{'CF.{_RTIR_Resolution}'} || '';
	print "$queue ID: $id ($state)\nCreated: $cdate\n$subj\nClassification: $class";
	if($rdate){ print "\nResolved: $rreason\t$rdate"; }
	print "\nIP List:\n$ipl\n\n";
}
