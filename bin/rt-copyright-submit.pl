#!/usr/bin/env perl

# Probably this could be done more generally by rt-incident-submit.
# So this is evil cargo-culting of my own code. Whatever, I've got work to do.

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
use XML::XPath;
use Socket;
use Net::IPv4Addr qw( :all ); # yeah, both this and Socket for gethostbyaddr.
use vars qw/$opt_f $opt_v $opt_x $opt_h $opt_c/;
use Getopt::Std;

getopts('f:v:x:hc');

my $debug = $opt_v || 0;
my $sclosed = $opt_c || 0;
my %config;

if($opt_h){
    print "Options: -f(config file), -v(debug), -x(xml file), -c(submit closed)\n";
    exit 0;
}
if($opt_f){
	%config = ISSRT::ConConn::GetConfig($opt_f);
} else {
	%config = ISSRT::ConConn::GetConfig();
}
# Set up Waterloo-specific subnets.
# This should go into a configuration file.
my @wirelessnets = ( "129.97.124.0/25","129.97.125.0/25" );
my @resnets = ("129.97.224.0/20","129.97.240.0/21","129.97.248.0/22",
	"129.97.252.0/22","129.97.124.128/25","129.97.125.128/25");

sub resolve() {
	my $inip = shift;
	my $foo = inet_aton($inip);
	return gethostbyaddr($foo,AF_INET) || "Unknown Hostname";
}

sub find_c() {
	my $inip = shift;
	if($debug > 0){ print ("find_c inip was $inip\n"); }
	foreach my $net (@wirelessnets){
		if( ipv4_in_network($net,$inip) ){
			return "Academic-Support";
		}
	}
	foreach my $net (@resnets){
		if( ipv4_in_network($net,$inip) ){
			return "ResNet";
		}
	}
	return "unclassified";
}

my $inXML = 0;
my $xmlString = "";
if ($opt_x){
   open(FILE, $opt_x);
   my @output =<FILE>;
   foreach my $line (@output){
	if( $line =~ m/<\?xml.*?>/) {
		$inXML = 1;
	}
	if($line =~ m#</Infringement>#) {
		$xmlString .= $line;;
		$inXML = 0;
	}
	if($inXML) {
		$xmlString .= $line;;
	}
}
}
my ($ch,$ts,$cid,$ip,$dname,$title,$ft,$dv,$fn,$constit) = "";

if($xmlString) {
	$xmlString =~ s/(\s)&(\s)/$1&amp;$2/;
	if($debug > 0) { print "\n--\nxmlstring is:\n . " . Dumper($xmlString) . "\n"; }
	my $xp = XML::XPath->new(xml => $xmlString);
	if($debug > 0) { print "\n---\nxp is:\n" . Dumper($xp) . "\n"; }
	$ch = $xp->findvalue("/Infringement/Complainant/Entity") || "Unknown Entity";
	$ts = $xp->findvalue("/Infringement/Source/TimeStamp") || "Unknown Timestamp";
	$cid = $xp->findvalue("/Infringement/Case/ID") || "Unknown CaseID";
	$ip = $xp->findvalue("/Infringement/Source/IP_Address") || "Unknown IP";
	$dname = $xp->findvalue("/Infringement/Source/DNS_Name") || &resolve($ip); # this needs better error-checking
	$title = $xp->findvalue("/Infringement/Content/Item/Title") || "Unknown Title";
	$fn = $xp->findvalue("/Infringement/Content/Item/FileName") || "Unknown Filename";
	$ft = $xp->findvalue("/Infringement/Content/Item/Type") || "Unknown Type";
	$dv = $xp->findvalue("/Infringement/Source/Deja_Vu") || "DejaVu unset";
	$ts =~ s/T.*//;
	$constit = &find_c($ip);
} else {
	die "DERP HERP\n";
}

my $subject = "Copyright complaint $cid $ts $ip";

my $rttext = qq|
Entity $ch
Date $ts
CaseID $cid
SourceIP $ip
FQDN $dname
Title $title
Type $ft
DejaVu $dv
|;

if($debug > 0){
	print qq|
Subject: $subject
Constituency: $constit

RT Text:
$rttext
|;
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

# Create the ticket.
my $ticket = RT::Client::REST::Ticket->new(
	rt => $rt,
	queue => "Incidents",
	subject => $subject,
	cf => {
		'Risk Severity' => 1,
		'_RTIR_Classification' => "Copyright",
		'_RTIR_Constituency' => $constit
	},
)->store(text => $rttext);
my $tid = $ticket->id;
print "New ticket's ID is $tid\n";

if($sclosed){
	if ($debug > 0){ print "Closing ticket $tid\n"; }
	# want to set CF.{_RTIR_State} to 'resolved', CF.{_RTIR_Resolution} to 'successfully resolved', and Status to 'resolved'
	my $ip_in_range = &find_c($ip);
	if ($constit eq "ResNet" || $ip_in_range eq "Academic-Support"){
	           my $t = $rt->edit(type => 'ticket', 
	                             id => $tid, 
	                             set => { status => 'resolved'}     
                                    );	
        }
}
