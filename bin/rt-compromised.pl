#!/usr/bin/env perl

# Report on compromised accounts for a given time frame.
# Ignores any incident with an abandoned state or resolution
# Mike Patterson <mike.patterson@uwaterloo.ca>
# in his guise as IST-ISS staff member, Oct 2012

# todo add a month-by-month option

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
use vars qw/$opt_s $opt_e $opt_c $opt_f $opt_v $opt_h $opt_x $opt_S/;
use Getopt::Std;

getopts('s:e:c:f:v:hxS');

my $debug = $opt_v || 0;
my ($ticket,$checkmonth,%config);
my (%classifications,%constituencies);

if($opt_h){
   print "Options: -s(start-date),-e(end-date), -c(constituency),-f(config file), -x (HTML), -v(debug), -S(Summary only)\n";
   exit 0;
}

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
AND CF.{Resolution} != 'abandoned'
AND CF.{Classification} = 'Compromised User Credentials'
|;
if ($const){
	$qstring = $qstring . " AND CF.{Constituency} = '$const'"
}
if($debug > 0){ print "Query string\n$qstring\n"; }

my @ids = $rt->search(
	type => 'ticket',
	query => $qstring
);

if($debug > 0){ print scalar @ids . " incidents\n"; }
if($debug > 1){	print Dumper(@ids); }

if($opt_x){
	print qq|
<table width="85%" border="1" summary="Compromised Accounts">
<caption>Compromised Accounts</caption>
<tr>
 <th scope="col">Incident</th>
 <th scope="col">Userid</th>
 <th scope="col">Constituency</th>
 <th scope="col">Subject</th>
 <th scope="col">RTIR link</th>
</tr>
|;
}

my $cnt = 0;
for my $id (@ids) {
	# show() returns a hash reference
	my ($ticket) = $rt->show(type=>'ticket',id=>$id);
	next if($ticket->{'Status'} eq 'abandoned'); # RT is stupid and SQL statement can't exclude state?
	$cnt++;
	next if($opt_S); # If we're only summarising, don't care about the rest
	my $conskey = $ticket->{'CF.{Constituency}'};
	$constituencies{$conskey} ||= 0;
	$constituencies{$conskey} += 1;
	my $pwned = $ticket->{'CF.{Userid}'} || 'Unset';
	if($opt_x){
		print qq|<tr><td>$id</td><td>$pwned</td><td>$conskey</td><td>$ticket->{'Subject'}</td>
		<td><a href="https://$config{hostname}/RTIR/Display.html?id=$id">RTIR link</a></td>
		|;
		# HTML output
	} else {
		print "$id\t$pwned\t$conskey\t$ticket->{'Subject'}\n";
	}
	if($debug > 2){
		print Dumper($ticket);
	}
}

my $msgtxt="RT Compromised Accounts report for $lm to $nm - total $cnt\n";

if($opt_x){
	print qq|</table><p>$msgtxt</p>|;
} else {
	print $msgtxt;
	print "$constituencies{$_}\t$_\n" for sort 
 		{ $constituencies{$b} <=> $constituencies{$a} } keys %constituencies;
}
