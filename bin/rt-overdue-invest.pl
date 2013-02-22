#!/usr/bin/env perl

#IST-ISS Co-op Cheng Jie Shi <cjshi@uwaterloo.ca> Feb 2013
#Supervisor: Mike Patterson <mike.patterson@uwaterloo.ca>

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;
use RT::Client::REST;
use Error qw|:try|;
use Date::Manip;
use ConConn;
use vars qw/ $opt_s $opt_e $opt_r $opt_E $opt_v $opt_f $opt_h/;
use Getopt::Std;

getopts('s:e:r:f:v:Eh');

my $overduemessage = qq|
Please note that no correspondence has been received for this ticket lately,
and that it is now overude.
|;

my $debug = $opt_v || 0;
my(%config,@list,$lm,$nm,$qstring);

if($opt_h){
        print "Options: -s(start-time), -e(end-time), -r(report on ticket ID), -E(Send Emails to correspondents), -f(config file), -v(debug)\n";
        print "If only -r is given, report for the ticket ID. If -r and -E are given, send Email for the ticket ID\n";
        exit 0;
}
 
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

#-s -e time options
if($opt_s && $opt_e){
  $lm = $opt_s;
  $nm = $opt_e;
  $qstring = qq|
    Queue = 'Investigations'
    AND Created > '$lm'
    AND Created < '$nm'
    AND CF.{_RTIR_State} = 'open'
    AND Due < '$tday'
    |;
  print "Overdue Investigations from $lm to $nm\n";
} elsif ($opt_s && (!$opt_e)){
  $lm = $opt_s;
  $nm = UnixDate("today","%Y-%m-%d");
  $qstring = qq|
    Queue = 'Investigations'
    AND Created > '$lm'
    AND Created < '$nm'
    AND CF.{_RTIR_State} = 'open'
    AND Due < '$tday'
    |;
  print "Overdue Investigations from $lm to $nm\n";
} elsif ((!$opt_s) && (!$opt_e)){
  $lm = $opt_s;
  $nm = UnixDate("today","%Y-%m-%d");
  $qstring = qq|
    Queue = 'Investigations'
    AND CF.{_RTIR_State} = 'open'
    AND Due < '$tday'
    |;
    print "Overdue Investigations\n";
}

if($debug > 0){ print "Query string\n$qstring\n"; }

my @ids = $rt->search(
	type => 'ticket',
	query => $qstring
);

if($debug > 0){	print scalar @ids . " investigations\n"; }
if($debug > 1){	print Dumper(@ids); }

#-E send Emails
if($opt_E && (!$opt_r)){
  foreach my $id (@ids) {
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
  	if(@corrspd){
              my $lastperson = $corrspd[$#corrspd];
              my $last = substr $lastperson, 24;
                   if( ($last ne "mpatters" ) && ($last ne "issminion") ){ # hardcoded lists of users are evil
                         push (@list, $id);
                    }
        }
  }

  # foreach my $overdue (@list){
    # if($debug > 4){
           # print "Would send email on $overdue\n";
    # } else {
          # my $msg = $rt->correspond(
          # ticket_id   => $overdue,
          # message     => $overduemessage,
      # );
    # }
  # }
}  	
else {   
  foreach my $id (@ids){
    #-r search if one particular ticket is overdue
    if($opt_r && (!$opt_E)){
      if ($id == $opt_r){
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
      	  printf "%-10s %-12s %-12s %-30s %-30s\n",	$id,$owner,$last,$ddate,$subj;
        } else {
          printf "%-10s %-12s %-12s %-30s %-30s\n",	$id,$owner,$owner,$ddate,$subj;
        }
      } # if that ticket is overdue, send Email to this ticket
    } elsif($opt_r && $opt_E){
        if ($id == $opt_r){
          # my $msg = $rt->correspond(
            # ticket_id   => $opt_r,
            # message     => $overduemessage,
          # );
      	   print "Email has been sent to $id\n"; 	
      	}
    }
    else{#print a report
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
             printf "%-10s %-12s %-12s %-30s %-30s\n",	$id,$owner,$last,$ddate,$subj;
        } else{
             printf "%-10s %-12s %-12s %-30s %-30s\n",	$id,$owner,$owner,$ddate,$subj;
        }
    }
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
