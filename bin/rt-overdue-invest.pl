#!/usr/bin/env perl

#IST-ISS Co-op Cheng Jie Shi <cjshi@uwaterloo.ca> Jan 2013
#Supervisor: Mike Patterson <mike.patterson@uwaterloo.ca>

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;
use RT::Client::REST;
use RT::Client::REST::Ticket;
use Error qw|:try|;
use Date::Manip;
use ConConn;

my $debug = 0;

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
	my @corrspd;
	my ($ticket) = $rt->show(type=>'ticket',id=>$id);
	my (@parent_id) = $rt->get_transaction_ids(parent_id => $id);
        foreach my $ele (@parent_id){
	  	my $name = $rt->get_transaction (parent_id => $id, id => $ele);
	  	my @des = $name -> {'Description'};
	  	if ($des[0] =~ /^Correspondence/){
	  	push(@corrspd, $des[0]);
		}	
	}
	my $lastperson = $corrspd[$#corrspd];
	if($debug > 0) {
		print Dumper($ticket);
	}
	my $subj = $ticket->{'Subject'};
	my $ddate = $ticket->{'Due'};
	my $owner = $ticket->{'Owner'};
	if(@corrspd){
	   my $lastperson = $corrspd[$#corrspd];
	   my $last = substr $lastperson, 24;
	   printf "%-10s %-12s %-12s %-30s %-30s\n",	
           $id,$owner,$last,$ddate,$subj;
        }else{
           printf "%-10s %-12s %-12s %-30s %-30s\n",	
           $id,$owner,$owner,$ddate,$subj;
        }
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
