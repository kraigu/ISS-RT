#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

# Look for Investigations that have gone past their due date
# Mike Patterson <mike.patterson@uwaterloo.ca>
# in his guise as IST-ISS staff member, 20 September 2012
# also look for Incidents which lack an Investigation
# blame same, 12 October 2012

use Data::Dumper;
use RT::Client::REST;
use Error qw|:try|;
use Date::Manip;
use ConConn;
use vars qw/$opt_f $opt_v $opt_h/;
use Getopt::Std;

getopts('f:v:h');
if($opt_h){
	print "Options: -f(config file), -v(debug)\n";
}else{
my $debug = 0;
if($opt_v){
  $debug = $opt_v
}
my %config;

if($opt_f){
	%config = ISSRT::ConConn::GetConfig($opt_f);
} else {
	%config = ISSRT::ConConn::GetConfig();
}

my $rt = RT::Client::REST->new(
	server => 'https://' . $config{hostname},
	timeout => 30,
);

try {
	$rt->login(username => $config{username}, password => $config{password});
} catch Exception::Class::Base with {
	die "problem logging in: ", shift->message;
};

my $tday = UnixDate("today","%Y-%m-%d");

my $qstring = qq|
Queue = 'Investigations'
AND CF.{_RTIR_State} = 'open'
AND Due < '$tday'
|;

if($debug > 0){ print "Query string\n$qstring\n"; }

my @ids = $rt->search(
	type => 'ticket',
	query => $qstring
);

if($debug > 0){	print scalar @ids . " investigations\n"; }
if($debug > 1){	print Dumper(@ids); }

print "Overdue Investigations\n";

for my $id (@ids) {
	# show() returns a hash reference
	my ($ticket) = $rt->show(type=>'ticket',id=>$id);
	if($debug > 0) {
		print Dumper($ticket);
	}
	my $subj = $ticket->{'Subject'};
	my $ddate = $ticket->{'Due'};
	my $owner = $ticket->{'Owner'};
	print "$id\t$owner\t$ddate\t$subj\n";
}

$qstring = qq|
Queue = 'Incidents'
AND CF.{_RTIR_State} = 'open'
|;

for my $id (@ids) {
	my ($ticket) = $rt->show(type=>'ticket',id=>$id);
	if($debug > 0) {
		print Dumper($ticket);
	}
	my $subj = $ticket->{'Subject'};
	my $owner = $ticket->{'Owner'};
}
}