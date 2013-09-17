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
my @wirelessnets = ( "129.97.124.0/23" );
my @resnets = ("129.97.131.0/24");

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
my @output;
if($opt_x) {
	open(FILE, $opt_x);
	@output = <FILE>;
}else {
	@output = <STDIN>;
}

foreach my $line (@output){
	if($inXML != -1 && m/<\?xml.*?>/) {
		$inXML = 1;
	}
	if($inXML != -1 && m#</Infringement>#) {
		$xmlString .= $line;
		$inXML = -1;
	}
	if($inXML == 1) {
		$xmlString .= $_;
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

#make sure the incident has not already been submitted
my $qstring = qq|
Queue = 'Incidents'
AND Subject LIKE 'Copyright% $cid '
|;

my $isrepeat = $rt->search(
	type => 'ticket',
	query => $qstring,
);

my $status = "open";
if($sclosed && ($constit eq "ResNet" || $constit eq "Academic-Support")) {
	$status = "resolved";
}

# Create the ticket.
unless($isrepeat) {
	my $ticket = RT::Client::REST::Ticket->new(
		rt => $rt,
		queue => "Incidents",
		subject => $subject,
		status => $status,
		cf => {
			'Risk Severity' => 1,
			'_RTIR_Classification' => "Copyright",
			'_RTIR_Constituency' => $constit,
			'_RTIR_State' => $status,
		},
	)->store(text => $rttext);
	print "New ticket's id is ", $ticket->id, "\n";
}