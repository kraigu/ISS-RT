#!/usr/bin/env perl

# Report on Incidents for a given time frame.
# Ignores Question Only incidents and any incident
# with an abandoned state or resolution (wtf RT?)
# Mike Patterson <mike.patterson@uwaterloo.ca>
# in his guise as IST-ISS staff member, Feb, Jul 2012 (and ongoing)
# also IST-ISS Co-op Cheng Jie Shi <cjshi@uwaterloo.ca> Feb 2013

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
use vars qw/ $opt_s $opt_e $opt_c $opt_l $opt_C $opt_L $opt_V $opt_v $opt_h $opt_f $opt_t/;
use Getopt::Std;

getopts('s:e:f:v:t:clCLVh');
my $debug = $opt_v || 0;

my ($ticket,$checkmonth);
my (%classifications,%constituencies,%config);
my($lm,$nm);

if($opt_f){
	%config = ISSRT::ConConn::GetConfig($opt_f);
} else {
	%config = ISSRT::ConConn::GetConfig();
}

#-s -e time options
if($opt_s && $opt_e){
	$lm = $opt_s;
	$nm = $opt_e	
} elsif ($opt_s && (!$opt_e)){
	$lm = $opt_s;
	$nm = UnixDate("today","%Y-%m-%d");
} elsif((!$opt_s) && (!$opt_e)){	
	$lm = UnixDate("-1m","%Y-%m-01");
	$nm = UnixDate("today","%Y-%m-01");
}

# check for a timeout value
my $timeout = $opt_t || 30;

my $qstring = qq|
Queue = 'Incidents'
AND Created > '$lm'
AND Created < '$nm'
AND CF.{Classification} != 'Question Only'
AND CF.{Resolution} != 'abandoned'
AND Status != 'abandoned'
AND CF.{Resolution} != 'false positive'
AND Status != 'rejected'
|;

my $rt = RT::Client::REST->new(
	server => 'https://' . $config{hostname},
	timeout => $timeout,
);

try {
	$rt->login(username => $config{username}, password => $config{password});
} catch Exception::Class::Base with {
	die "problem logging in: ", shift->message;
};

if($opt_h){
	print "Available options: -s (start-date),  -e (end-date), -c (include Copyright), -l (include LE request), -C (Copyright only), -L (LE request only), -V (verbose report), -v (enable debugging) -t (timeout)\n";
	print "If no dates are given, assume the previous calendar month. If only a start date is given, assume the current date as the end date\n";
	exit 0;
}

#-l include 'LE Request'
if($opt_l && (!$opt_c) && (!$opt_L) && (!$opt_C)){
	$qstring .= qq|AND CF.{Classification} != 'Copyright'|; 
}#-c include 'Copyright'
elsif((!$opt_l) && $opt_c && (!$opt_L) && (!$opt_C)){
	$qstring .= qq|AND CF.{Classification} != 'LE request'|;
}#-c -l include 'Copyright' and 'LE Request'
elsif($opt_l && $opt_c && (!$opt_L) && (!$opt_C)){
	#do nothing
}#ouput for no options given. default to print anything other than 'LE Request' and 'Copyright'
elsif((!$opt_l) && (!$opt_c) && (!$opt_L) && (!$opt_C)){
	$qstring .= qq|AND CF.{Classification} != 'LE request' AND CF.{Classification} != 'Copyright'|;
}#-L include ONLY 'LE Request'
elsif((!$opt_l) && (!$opt_c) && $opt_L && (!$opt_C)){
	$qstring .= qq|AND CF.{Classification} = 'LE request'|;
}#-C include ONLY 'Copyright'
elsif((!$opt_l) && (!$opt_c) && (!$opt_L) && $opt_C){
	$qstring .= qq|AND CF.{Classification} = 'Copyright'|;
}#-C -L
elsif((!$opt_l) && (!$opt_c) && $opt_L && $opt_C){
 	$qstring .= qq|
AND(
	CF.{Classification} = 'LE request'
	OR
	CF.{Classification} = 'Copyright'
)
|;
}

if($debug > 0){ print "Query string\n$qstring\n"; }

my @ids = $rt->search(
	type => 'ticket',
	query => $qstring,
	orderby => '+created'
);

if($debug > 0){	print scalar @ids . " incidents\n"; }
if($debug > 1){	print Dumper(@ids); }

if($opt_V) {
	print "RT Incident report for $lm to $nm\n";
	print qq|"RT number","Created",Classification","Constituency","Subject"\n|;
	for my $id (@ids) {
		# show() returns a hash reference
		my ($ticket) = $rt->show(type=>'ticket',id=>$id);
		my $classif = $ticket->{'CF.{Classification}'} || "Unclassified";
		my $constit = $ticket->{'CF.{Constituency}'};
		my $subj = $ticket->{'Subject'};
		my $tickdate = $ticket->{'Created'};
		print qq|"$id","$tickdate","$classif","$constit","$subj"\n|;
		if($debug > 2) {
			print "DEBUG:\n";
			print Dumper($ticket);
		}
	}
}else {		
	for my $id (@ids) {
		# show() returns a hash reference
		my ($ticket) = $rt->show(type=>'ticket',id=>$id);
		if ($debug > 1){ print $ticket; }
		next if($ticket->{'Status'} eq 'abandoned'); # RT is stupid and SQL statement can't exclude state?
		my $classkey = $ticket->{'CF.{Classification}'};
		my $conskey = $ticket->{'CF.{Constituency}'};
		$classifications{$classkey} ||= 0;
		$classifications{$classkey} += 1; # hurray for mr cout
		$constituencies{$conskey} ||= 0;
		$constituencies{$conskey} += 1;
		if($debug > 1){
			print "$id\t$conskey\t$ticket->{'Subject'}\n";
		}
		if($debug > 2){
			print Dumper($ticket);
		}
	}
	
	print "RT Incident report for $lm to $nm\nClassifications\n";
	
	print "$classifications{$_}\t$_\n" for sort 
	 { $classifications{$b} <=> $classifications{$a} } keys %classifications;
	
	print "\nConstituencies\n";
	
	print "$constituencies{$_}\t$_\n" for sort 
	 { $constituencies{$b} <=> $constituencies{$a} } keys %constituencies;
}

