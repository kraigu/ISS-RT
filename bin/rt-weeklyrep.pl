#!/usr/bin/env perl

# Report on Incidents for a given time frame.
# Ignores Question Only incidents and any incident
#  resolved as abandoned.
# Mike Patterson <mike.patterson@uwaterloo.ca>
# in his guise as IST-ISS staff member, Feb 2012

use strict;
use warnings;

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

# default to the previous week's issues. Sort of.
# RT's kind of weird about how it does date comparisons.
my $lm = $ARGV[0] || UnixDate("-6d","%Y-%m-%d");
my $nm = $ARGV[1] || UnixDate("+1d","%Y-%m-%d");

my $rt = RT::Client::REST->new(
	server => 'https://' . $config{hostname},
	timeout => 30,
);

try {
	$rt->login(username => $config{username}, password => $config{password});
} catch Exception::Class::Base with {
	die "problem logging in: ", shift->message;
};

my $qstring = qq|
Queue = 'Incidents'
AND Created > '$lm'
AND Created < '$nm'
AND (
 	CF.{_RTIR_Resolution} != 'abandoned' 
 	OR
	CF.{_RTIR_Classification} != 'Question Only'
	OR
	CF.{_RTIR_Status} != 'rejected'
)
|;

if($debug > 0){ print "Query string\n$qstring\n"; }

my @ids = $rt->search(
	type => 'ticket',
	query => $qstring,
	orderby => '+created'
);

if($debug > 0){	print scalar @ids . " incidents\n"; }
if($debug > 1){	print Dumper(@ids); }

print "RT Incident report for $lm to $nm\n";
print qq|"RT number","Created",Classification","Constituency","Subject"\n|;

for my $id (@ids) {
	# show() returns a hash reference
	my ($ticket) = $rt->show(type=>'ticket',id=>$id);
	my $classif = $ticket->{'CF.{_RTIR_Classification}'} || "Unclassified";
	my $constit = $ticket->{'CF.{_RTIR_Constituency}'};
	my $subj = $ticket->{'Subject'};
	my $tickdate = $ticket->{'Created'};
	print qq|"$id","$tickdate","$classif","$constit","$subj"\n|;
	if($debug > 1) {
		print "DEBUG:\n";
		print Dumper($ticket);
	}
}

