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

#output goes to stderr so that it shows up in the procmail logfile
select STDERR;

my $debug = 0;

my %config = ISSRT::ConConn::GetConfig();

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
while(<>){
	if($inXML != -1 && m/<\?xml.*?>/) {
		$inXML = 1;
	}
	if($inXML != -1 && m#</Infringement>#) {
		$xmlString .= $_;;
		$inXML = -1;
	}
	if($inXML == 1) {
		$xmlString .= $_;;
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

#make sure the incident has not been already submitted
my $qstring = qq|
Queue = 'Incidents'
AND Subject LIKE 'Copyright% $cid ' 
|;

my $isrepeat = $rt->search(
	type => 'ticket',
	query => $qstring,
);


# Create the ticket.
unless($isrepeat) {
	my $ticket = RT::Client::REST::Ticket->new(
		rt => $rt,
		queue => "Incidents",
		subject => $subject,
		status => 'resolved',
		cf => {
			'Risk Severity' => 1,
			'_RTIR_Classification' => "Copyright",
			'_RTIR_Constituency' => $constit,
			'_RTIR_State' => 'resolved',
		},
	)->store(text => $rttext);
	print "New ticket's ID is ", $ticket->id, "\n";
}
# Submitted open. Shoot me now.
