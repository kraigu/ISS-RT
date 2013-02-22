#!/usr/bin/env perl

# Attempt to set the Userid custom field for a given range of Incidents.
# Assumption: the word "comprmomised" will be in the subject.
# Mike Patterson, uWaterloo IST-ISS, Oct 2012.

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;
use Config::General;
use RT::Client::REST;
use RT::Client::REST::Ticket;
use Error qw|:try|;
use Date::Manip;
use ConConn;
use vars qw/ $opt_s $opt_e $opt_f $opt_v $opt_h/;
use Getopt::Std;

getopts('s:e:f:v:h');

my $debug = $opt_v || 0;
my ($ticket,$checkmonth);
my (%classifications,%constituencies,%config);

if($opt_h){
   print "Options: -s (start-date), -e (end-date), -f (config file), -v(debug)\n";
}else{
if($opt_f){
	%config = ISSRT::ConConn::GetConfig($opt_f);
} else {
	%config = ISSRT::ConConn::GetConfig();
}

# default to the previous month's issues. Sort of.
my $lm = $opt_s || UnixDate("-1m -1d","%Y-%m-%d");
my $nm = $opt_e || UnixDate("today","%Y-%m-01");

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
AND CF.{_RTIR_Resolution} != 'abandoned'
AND CF.{_RTIR_Classification} = 'Compromised User Credentials'
|;

if($debug > 0){ print "Query string\n$qstring\n"; }

my @ids = $rt->search(
	type => 'ticket',
	query => $qstring
);

if($debug > 0){	print scalar @ids . " incidents\n"; }
if($debug > 1){	print Dumper(@ids); }

for my $id (@ids) {
	# show returns a hash reference
	my ($ticket) = $rt->show(type=>'ticket',id=>$id);
	next if($ticket->{'CF.{_RTIR_State}'} eq 'abandoned'); # RT is stupid and SQL statement can't exclude state?
	next if($ticket->{'CF.{Userid}'});
	my $subj = $ticket->{'Subject'};
	next unless $subj =~ /compromised/;
	my ($pwned,$rest) = split(/ /,$subj);
	print("Setting $id userid value to $pwned\n");
	# The following is probably really stupid if you know your perl.
	# I don't, so I'll be stupid. It works.
	my $t2 = RT::Client::REST::Ticket->new(
		rt => $rt,
		id => $id,
	)->retrieve;
	$t2->cf('Userid' => $pwned);
	if($debug > 2){
		print Dumper($t2);
	}
	$t2->store;
}
}