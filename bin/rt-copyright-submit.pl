#!/usr/bin/env perl

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
use MIME::QuotedPrint::Perl;
use File::Temp qw/ tempfile /;

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
my (@wirelessnets, @resnets) = ();
my $value = $config{"wireless"};
if(ref($value) eq "ARRAY") {
	@wirelessnets = @{$value};
}else {
	push(@wirelessnets, $value);
}
$value = $config{"resnet"};
if(ref($value) eq "ARRAY") {
	@resnets = @{$value};
}else {
	push(@resnets, $value);
}

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
			return "Academic Support";
		}
	}
	foreach my $net (@resnets){
		if( ipv4_in_network($net,$inip) ){
			return "ResNet";
		}
	}
	return "unclassified";
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

my $quoted = 0;
my $inXML = 0;
my $xmlString = "";
my @notices = ();
my @output;
if($opt_x) {
	open(FILE, $opt_x);
	@output = <FILE>;
}else {
	@output = <STDIN>;
}

my ($tmp, $attachment) = tempfile(SUFFIX => ".txt");
foreach my $line (@output){
	print $tmp $line;
	if($line =~ m/<\?xml.*?>/) {
		$inXML = 1;
	}
	if($line =~ m#</Infringement>#) {
		$xmlString .= $line;
		$xmlString = decode_qp($xmlString) if $quoted;
		$inXML = 0;
		$quoted = 0;
		push(@notices, $xmlString);
		$xmlString = "";
	}
	if($inXML) {
		$xmlString .= $line;
	}
	if($line =~ m/version=3D/) {
		$quoted = 1;
	}
}
close($tmp) || warn "close failed, attachment may not be submitted: $!";

my ($ch,$ts,$cid,$ip,$dname,$title,$ft,$dv,$fn,$constit) = "";

for my $notice (@notices) {
	if($notice) {
		$notice =~ s/(\s)&(\s)/$1&amp;$2/;
		if($debug > 0) { print "\n--\nxmlstring is:\n . " . Dumper($notice) . "\n"; }
		my $xp = XML::XPath->new(xml => $notice);
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
	Filename $fn
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

	#make sure the incident has not already been submitted
	my $qstring = qq|
	Queue = 'Incidents'
	AND Subject LIKE 'Copyright% $cid $ts $ip'
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
	unless($isrepeat || $cid eq "Unknown CaseID") {
		my $ticket = RT::Client::REST::Ticket->new(
			rt => $rt,
			queue => "Incidents",
			subject => $subject,
			status => $status,
			cf => {
				'Risk Severity' => 1,
				'Classification' => "Copyright",
				'Constituency' => $constit,
			},
		)->store(text => $rttext);
		$ticket->comment(message => "original complaint", attachments => [$attachment]);
		print "New ticket's id is ", $ticket->id, "\n" if($debug > 0);
	}
}