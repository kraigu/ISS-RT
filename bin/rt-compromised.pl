#!/usr/bin/env perl

# Report on compromised accounts for a given time frame.
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
use vars qw/ $opt_s $opt_e $opt_c $opt_f $opt_v $opt_h/;
use Getopt::Std;

getopts('s:e:c:f:v:h');

my $debug = $opt_v || 0;
my ($ticket,$checkmonth,%config);
my (%classifications,%constituencies);

if($opt_h){
   print "Options: -s(start-date),-e(end-date), -c(constituency),-f(config file), -v(debug)\n";
}else{

# default to the previous month's issues. Sort of.
my $lm = $opt_s || UnixDate("-1m -1d","%Y-%m-%d");
my $nm = $opt_e || UnixDate("today","%Y-%m-01");
my $const = $opt_c || "";

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
if ($const){
	$qstring = $qstring . " AND CF.{_RTIR_Constituency} = '$const'"
}
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
	my $conskey = $ticket->{'CF.{_RTIR_Constituency}'};
	$constituencies{$conskey} ||= 0;
	$constituencies{$conskey} += 1;
	my $pwned = $ticket->{'CF.{Userid}'} || 'Unset';
	print "$id\t$pwned\t$conskey\t$ticket->{'Subject'}\n";
	if($debug > 2){
		print Dumper($ticket);
	}
}

print "RT Compromised Accounts report for $lm to $nm\n";

print "\nConstituencies\n";

print "$constituencies{$_}\t$_\n" for sort 
 { $constituencies{$b} <=> $constituencies{$a} } keys %constituencies; 
}