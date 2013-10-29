#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Config::General;
use RT::Client::REST;
use RT::Client::REST::Ticket;
use Error qw|:try|;
use Date::Manip;
use ConConn;
use Net::IPv4Addr qw( :all );
use vars qw/$opt_f $opt_v $opt_x $opt_h $opt_c $opt_i/;
use Getopt::Std;
use RINO::Client;
use MIME::Parser;
use IO::Uncompress::Unzip qw(unzip $UnzipError);

getopts('f:v:x:hci');

my $debug = $opt_v || 0;
my $sclosed = $opt_c || 0;
my $ignore = $opt_i || 0;
my %config;

if($opt_h){
    print "Options: -f(config file), -v(debug), -x(xml file), -c(submit closed), -i(ignore lesser networks)\n";
    exit 0;
}
if($opt_f){
	%config = ISSRT::ConConn::GetConfig($opt_f);
} else {
	%config = ISSRT::ConConn::GetConfig();
}

#configure the Waterloo specific subnets
my (@wirelessnets, @resnets, @tor) = ();
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
$value = $config{"tor"};
if(ref($value) eq "ARRAY") {
	@tor = @{$value};
}else {
	push(@tor, $value);
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
	foreach my $net (@tor) {
		if( ipv4_in_network($net, $inip) ){
			return "Tor";
		}
	}
	return "unclassified";
}

sub submit_ticket() {
	my $rttext = shift;
	my $subject = shift;
	my $constit = shift;
	my $rt = shift;
	my $ip = shift;

	my $status = "open";
	if($sclosed && ($constit eq "ResNet" || $constit eq "Academic-Support" || $constit eq "Tor")) {
		$status = "resolved";
	}
	
	$rttext .= "\nActual Constituency: Wireless" if(ipv4_in_network("129.97.124.0/23", $ip));
	
	unless($ignore && ($constit eq "ResNet" || $constit eq "Academic-Support" || $constit eq "Tor")) {
		my $ticket = RT::Client::REST::Ticket->new(
			rt => $rt,
			queue => "Incidents",
			subject => $subject,
			status => $status,
			cf => {
				'Risk Severity' => 1,
				'_RTIR_Constituency' => $constit,
				'_RTIR_State' => $status,
			},
		)->store(text => $rttext);
	}
}

sub matches_previous() {
	my $parent_id = shift;
	my $time = shift;
	my $rt = shift;
	my @attachments = $rt->get_attachment_ids(id => $parent_id);
	my $matches = 0;

	return 1 if $rt->show(type => 'ticket', id => $parent_id)->{"Subject"} =~ /$time/;

	for(@attachments) {
		my $attachment = $rt->get_attachment(parent_id => $parent_id, id => $_);
		$matches = 1 if($attachment->{"Content"} =~ /Date:.*$time/);
	}
	
	return $matches;
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

my $xmlString = "";
if($opt_x) {
	open(FILE, $opt_x);
	for(<FILE>) {
		$xmlString .= $_;
	}
}else {
	my $parser = new MIME::Parser;
	$parser->output_to_core(1);
	my $email = $parser->parse(\*STDIN);

	#assuming attachment is the second part of the message	
	my $part = $email->parts(1);
	my $decoded = $part->bodyhandle->open("r");
	my $unzip = new IO::Uncompress::Unzip $decoded or die "unzip failed: $UnzipError\n";

	until($unzip->eof) {
		$xmlString .= $unzip->getline;
	}
}


my $rino = RINO::Client->new(iodef => $xmlString);
my $incidents = $rino->to_simple;

for(@$incidents) {
	my ($id, $sip, $dname, $port, $desc, $time, $extra, $constit, $subject, $rttext) = "";
	$id = $_->{"IncidentID"};
	$sip = $_->{"Address"};
	$dname = $_->{"Destination"};
	$port = $_->{"Port"};
	$desc = $_->{"Description"};
	$time = $_->{"DetectTime"};
	$extra = $_->{"AdditionalData"};
	$constit = &find_c($sip);
	
	$subject = "REN-ISAC incident $id $time";
	$rttext = qq|
	ID $id
	Date $time
	SourceIP $sip
	DestinationIP $dname
	Port $port
	Description $desc
	Additional $extra
	|;
		
	my @matches = $rt->search(
		type => 'ticket',
		query => qq|
		Queue = 'Incidents'
		AND Subject LIKE 'REN-ISAC%$id%'|,
	);

	if(@matches) {
		unless(&matches_previous($matches[0], $time, $rt)) {
			$rt->comment(
				ticket_id => shift @matches,
				message => $rttext,
			);
		}
	}else {
		&submit_ticket($rttext, $subject, $constit, $rt, $sip);
	}
}

