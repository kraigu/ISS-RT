#!/usr/bin/env perl

# IST-ISS Co-op Cheng Jie Shi <cjshi@uwaterloo.ca> Feb 2013
# Modify exsiting script from Mike Patterson
 
# Report on Incidents for a given time frame.
# Ignores Question Only incidents and any incident
# with an abandoned state or resolution (wtf RT?)
# Mike Patterson <mike.patterson@uwaterloo.ca>
# in his guise as IST-ISS staff member, Feb, Jul 2012

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
use vars qw/ $opt_s $opt_e $opt_c $opt_l $opt_C $opt_L $opt_v $opt_d $opt_h/;
use Getopt::Std;

getopts('s:e:clCLvdh');
my $start_run = time();
my $debug = 0;

my ($ticket,$checkmonth);
my (%classifications,%constituencies);
my($lm,$nm,$qstring);

my %config = ISSRT::ConConn::GetConfig();
if($opt_h){
print "Available options: -s (start-date),  -e (end-date), -c (include Copyright), -l (include LE request), -C (Copyright only), -L (LE request only), -v (verbose report), -d (enable debugging)";
print "\n";
}
#-s -e time options
if($opt_s && $opt_e){
  $lm = $opt_s;
  $nm = $opt_e	
}elsif ($opt_s && (!$opt_e)){
  $lm = $opt_s;
  $nm = UnixDate("today","%Y-%m-%d");
}elsif((!$opt_s) && (!$opt_e)){
 $lm = UnixDate("-1m","%Y-%m-01");
 $nm = UnixDate("today","%Y-%m-01");
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

#-v CSV output from weeklyrep.pl
if($opt_v){
  if($opt_l && (!$opt_c) && (!$opt_L) && (!$opt_C)){
  $qstring = qq|
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
  AND CF.{_RTIR_Classification} != 'Copyright'
|; 
}#-c include 'Copyright'
elsif((!$opt_l) && $opt_c && (!$opt_L) && (!$opt_C)){
  $qstring = qq|
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
  AND CF.{_RTIR_Classification} != 'LE request'
|;
}#-c -l include 'Copyright' and 'LE Request'
elsif($opt_l && $opt_c && (!$opt_L) && (!$opt_C)){
  $qstring = qq|
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
}#ouput for no options given. default to print anything other than 'LE Request' and 'Copyright'
elsif((!$opt_l) && (!$opt_c) && (!$opt_L) && (!$opt_C)){
  $qstring = qq|
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
  AND CF.{_RTIR_Classification} != 'LE request'
  AND CF.{_RTIR_Classification} != 'Copyright'
|;
}#-L include ONLY 'LE Request'
elsif((!$opt_l) && (!$opt_c) && $opt_L && (!$opt_C)){
  $qstring = qq|
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
  AND CF.{_RTIR_Classification} = 'LE request'
|;
}#-C include ONLY 'Copyright'
elsif((!$opt_l) && (!$opt_c) && (!$opt_L) && $opt_C){
  $qstring = qq|
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
  AND CF.{_RTIR_Classification} = 'Copyright'
|;
}# -C -L
elsif((!$opt_l) && (!$opt_c) && $opt_L && $opt_C){
  $qstring = qq|
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
  AND (CF.{_RTIR_Classification} = 'LE request'
       OR
       CF.{_RTIR_Classification} = 'Copyright'
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
}else{
#-l include 'LE Request'
if($opt_l && (!$opt_c) && (!$opt_L) && (!$opt_C)){
  $qstring = qq|
  Queue = 'Incidents'
  AND Created > '$lm'
  AND Created < '$nm'
  AND CF.{_RTIR_Classification} != 'Question Only'
  AND CF.{_RTIR_Resolution} != 'abandoned'
  AND CF.{_RTIR_Status} != 'rejected'
  AND CF.{_RTIR_Classification} != 'Copyright'
|; 
}#-c include 'Copyright'
elsif((!$opt_l) && $opt_c && (!$opt_L) && (!$opt_C)){
  $qstring = qq|
  Queue = 'Incidents'
  AND Created > '$lm'
  AND Created < '$nm'
  AND CF.{_RTIR_Classification} != 'Question Only'
  AND CF.{_RTIR_Resolution} != 'abandoned'
  AND CF.{_RTIR_Status} != 'rejected'
  AND CF.{_RTIR_Classification} != 'LE request'
|;
}#-c -l include 'Copyright' and 'LE Request'
elsif($opt_l && $opt_c && (!$opt_L) && (!$opt_C)){
  $qstring = qq|
  Queue = 'Incidents'
  AND Created > '$lm'
  AND Created < '$nm'
  AND CF.{_RTIR_Classification} != 'Question Only'
  AND CF.{_RTIR_Resolution} != 'abandoned'
  AND CF.{_RTIR_Status} != 'rejected'
|; 
}#ouput for no options given. default to print anything other than 'LE Request' and 'Copyright'
elsif((!$opt_l) && (!$opt_c) && (!$opt_L) && (!$opt_C)){
  $qstring = qq|
  Queue = 'Incidents'
  AND Created > '$lm'
  AND Created < '$nm'
  AND CF.{_RTIR_Classification} != 'Question Only'
  AND CF.{_RTIR_Resolution} != 'abandoned'
  AND CF.{_RTIR_Status} != 'rejected'
  AND CF.{_RTIR_Classification} != 'LE request'
  AND CF.{_RTIR_Classification} != 'Copyright'
|;
}#-L include ONLY 'LE Request'
elsif((!$opt_l) && (!$opt_c) && $opt_L && (!$opt_C)){
  $qstring = qq|
  Queue = 'Incidents'
  AND Created > '$lm'
  AND Created < '$nm'
  AND CF.{_RTIR_Classification} != 'Question Only'
  AND CF.{_RTIR_Resolution} != 'abandoned'
  AND CF.{_RTIR_Status} != 'rejected'
  AND CF.{_RTIR_Classification} = 'LE request'
|;
}#-C include ONLY 'Copyright'
elsif((!$opt_l) && (!$opt_c) && (!$opt_L) && $opt_C){
  $qstring = qq|
  Queue = 'Incidents'
  AND Created > '$lm'
  AND Created < '$nm'
  AND CF.{_RTIR_Classification} != 'Question Only'
  AND CF.{_RTIR_Resolution} != 'abandoned'
  AND CF.{_RTIR_Status} != 'rejected'
  AND CF.{_RTIR_Classification} = 'Copyright'
|;
}#-C -L
elsif((!$opt_l) && (!$opt_c) && $opt_L && $opt_C){
  $qstring = qq|
  Queue = 'Incidents'
  AND Created > '$lm'
  AND Created < '$nm'
  AND CF.{_RTIR_Classification} != 'Question Only'
  AND CF.{_RTIR_Resolution} != 'abandoned'
  AND CF.{_RTIR_Status} != 'rejected'
  AND (CF.{_RTIR_Classification} = 'LE request'
       OR
       CF.{_RTIR_Classification} = 'Copyright'
       )     
|;
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
	my $classkey = $ticket->{'CF.{_RTIR_Classification}'};
	my $conskey = $ticket->{'CF.{_RTIR_Constituency}'};
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

#-d option
my $end_run = time();
if($opt_d){
  my $run_time = $end_run - $start_run;   
  print  "Query took $run_time seconds\n"; 
}

