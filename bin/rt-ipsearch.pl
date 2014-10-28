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
use vars qw/$opt_s $opt_f $opt_v $opt_o $opt_h/;
use Getopt::Std;

getopts('s:f:v:oh');

my $debug = $opt_v || 0;
my %config;
my ($ticket,$checkmonth,$ipsearch);
my (%classifications,%constituencies);

if ($opt_h){
	print "Options: -s(IP address), -f(config file), -o(show if there are open RTS), -v(debug)\n";
	exit 0;
}

if($opt_f){
	%config = ISSRT::ConConn::GetConfig($opt_f);
} 
else {
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

if( !($opt_s) && scalar @ARGV == 1) { # we got precisely one argument
	$ipsearch = $ARGV[0];
} else { # we got multiple arguments, one of which might be the required -s
	$ipsearch = $opt_s || die "No IP\n";
}

die "$ipsearch doesn't look like an IPv4 address\n" unless $ipsearch =~ /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/;

my $qstring = qq|
(Queue = 'Incidents' OR Queue = 'Investigations')
AND CF.{IP} = '$ipsearch'
|;
if($debug > 0){ print "Query string\n$qstring\n"; }

my @ids = $rt->search(
	type => 'ticket',
	query => $qstring,
	orderby => '-created'
);

if($debug > 0){	print scalar @ids . " incidents\n"; }
if($debug > 1){	print Dumper(@ids); }

for my $id (@ids) {
	# show() returns a hash reference
	my ($ticket) = $rt->show(type=>'ticket',id=>$id);
	if($debug > 0) {
		print Dumper($ticket);
	}
	my $class = $ticket->{'CF.{Classification}'} || 'none';
	my $ipl = $ticket->{'CF.{IP}'};
	my $subj = $ticket->{'Subject'};
	my $state = $ticket->{'Status'};
	if ($opt_o){
	    if($state eq "open"){
            print 1;
	    	exit 1;		
	    }else{
			print 0;
			exit 0;	
	    }	
	}
	my $queue = $ticket->{'Queue'};
	my $cdate = $ticket->{'Created'};
	my $rdate = $ticket->{'Resolved'} || '';
	my $rreason = $ticket->{'CF.{Resolution}'} || '';
	print "$queue ID: $id ($state)\nCreated: $cdate\n$subj\nClassification: $class";
	if($rdate){ print "\nResolved: $rreason\t$rdate"; }
	print "\nIP List:\n$ipl\n\n";
}