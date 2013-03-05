#!/usr/bin/env perl

#IST-ISS Co-op Cheng Jie Shi <cjshi@uwaterloo.ca> Mar 2013
#Supervisor: Mike Patterson <mike.patterson@uwaterloo.ca>

use strict;
use warnings;
use Date::Manip;
use Data::Dumper;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Error qw|:try|;
use RT::Client::REST::Ticket;
use ConConn;
use vars qw/$opt_p $opt_v $opt_h/;
use Getopt::Std;

getopts('pv:h');
  
if($opt_h){
    print "Options: -p(print output),-v(debug)\n";
    exit 0;
}

my %uniip;
my $debug = $opt_v || 0;

sub newticket{
       my $text = $_[0];
       my $subject = "Combined Report";
       my %config  = ISSRT::ConConn::GetConfig();
       my $rt = RT::Client::REST->new(
          	server => 'https://' . $config{hostname},
        	timeout => 30,
        );

       try {
               	 $rt->login(username => $config{username}, password => $config{password});
       } catch Exception::Class::Base with {
	         die "problem logging in: ", shift->message;
       };

       my $ticket = RT::Client::REST::Ticket->new(
             rt => $rt,
             queue => "Incidents",
             subject => $subject,
       )->store(text => $text);
       print "New ticket's ID is ", $ticket->id, "\n";
}

sub trigger_event{
     my $trig_ip = $_[0];
     my $trigger;
     my @result = `sn-goodsids.rb`;
     foreach my $line (@result){
           chomp($line);
           my @curline = split(" ", $line);
           my $scrip = $curline[6];
           my $desip = $curline[7];
           if($trig_ip eq $scrip || $trig_ip eq $desip){
                 $line = $line."\n";
                 $trigger = $trigger.$line
           }
     }
     return $trigger;
}

sub find_exception{
     my @Exception_SID = ISSRT::ConConn::getSID();
     my $trig_events = trigger_event($_[0]);
     my @trig_events = split("\n", $trig_events);
     foreach my $event (@trig_events){
         my @line = split(" ",$event);
         my $gid_sid = $line[4];
         my $ip;
         my $scr_ip = $line[6];
         my $des_ip = $line[7];
         if($scr_ip =~ /129.97./){
               $ip = $scr_ip
         } elsif ($des_ip =~ /129.97./){
               $ip = $des_ip
         }
         foreach my $line (@Exception_SID){
               chomp($line);
               my @curline = split(" ", $line);
               my $e_gidsid =  $curline[0];
               my $e_ip = $curline[1];
               if ( ($gid_sid eq $e_gidsid) && ($ip eq $e_ip) ){
                     return "true";#the given IP has an exception     
               } 
         }
     }     
}

my @output = `sn-goodsids.rb`;
foreach my $line (@output){
	chomp($line);
        my @currline = split(" ", $line);
        my $scrIP = $currline[6];
        my $desIP = $currline[7];
        if($scrIP =~ /129.97./){
              $uniip{$scrIP} ++;
        }
        if($desIP =~ /129.97./){
              $uniip{$desIP} ++;      
        }       	
}

foreach my $key (keys %uniip){
        my ($snfindip_today,$ibdump,$qr_symsearch,$gid);
        my $result = `rt-ipsearch.pl -s $key -o`;
        if ($debug > 0){
              print "Ip address = $key and ipsearch = $result\n";
        }
        if ($result eq "0"){
              my $trig_event = trigger_event($key);
              eval {
                    local $SIG{ALRM} = sub { die "alarm\n" }; 
                    alarm 30;
                    $ibdump = `IBDump.pl -i $key`;
                    alarm 0;
              };
              if ($@) {
                    die unless $@ eq "alarm\n";
                    print "IBDump die\n";
              }              
              eval {
                    local $SIG{ALRM} = sub { die "alarm\n" }; 
                    alarm 300;
                    $snfindip_today = `sn-findip.rb -i $key -p`;
                    $gid = 
                    alarm 0;
              };
              if ($@) {
                    die unless $@ eq "alarm\n";
                    print "Findip die\n";
              }
              eval {
                    local $SIG{ALRM} = sub { die "alarm\n" }; 
                    alarm 300;
                    $qr_symsearch = `qr-symsearch.pl -i $key `;
                    alarm 0;
              };
              if ($@) {
                    die unless $@ eq "alarm\n";
                    print "Symsearch die\n";
              }
              my $body = "Trigger Event(s):\n".$trig_event."\n".$ibdump."\n".$snfindip_today."\n".$qr_symsearch;
              if ($opt_p){
                     print $body."\n";
              } else {
                    if (find_exception($key) ne "true"){
                           #print "Created a RT for $key\n";
                           #newticket($body);
                    }       
              }    
        }
}
