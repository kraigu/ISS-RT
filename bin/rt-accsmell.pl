#!/usr/bin/env perl

# Get a list of compromised account Incidents without the userid field set
# Ignores any incident with an abandoned state or resolution
# Mike Patterson <mike.patterson@uwaterloo.ca>
# in his guise as IST-ISS staff member, Oct 2012

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
use vars qw/ $opt_s $opt_e $opt_f $opt_v $opt_h/;
use Getopt::Std;

getopts('s:e:f:v:h');
my $debug = $opt_v || 0;

if($opt_h){
     print "Options: -s(start-time), -e(end-time), -f(config file), -v(debug)\n";
}else{

my ($ticket,$checkmonth,%config);
my (%classifications,%constituencies);



# default to the previous month's issues. Sort of.
my $lm = $opt_s || UnixDate("-1m -1d","%Y-%m-%d");
my $nm = $opt_e || UnixDate("today","%Y-%m-01");

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
	# show() returns a hash reference
	my ($ticket) = $rt->show(type=>'ticket',id=>$id);
	next if($ticket->{'CF.{_RTIR_State}'} eq 'abandoned'); # RT is stupid and SQL statement can't exclude state?
	next if($ticket->{'CF.{Userid}'});
	my $subj = $ticket->{'Subject'};
	next unless $subj =~ /compromised/;
	my ($pwned,$rest) = split(/ /,$subj);
	print "$id\t$subj\tGuessing $pwned\n";
	if($debug > 2){
		print Dumper($ticket);
	}
}
}