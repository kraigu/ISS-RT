#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use RT::Client::REST;
use RT::Client::REST::Ticket;
use Error qw|:try|;
use Text::CSV;
use IO::String;
use ConConn;
use Net::IPv4Addr qw( :all );
use vars qw/$opt_f $opt_v $opt_h $opt_c $opt_i/;
use Getopt::Std;
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use MIME::Base64;
use Data::Dumper;
use LWP::UserAgent;

getopts('f:v:hci');

my $rt;

my $debug = $opt_v || 0;
my $sclosed = $opt_c || 0;
my $ignore = $opt_i || 0;
my %config;

if($opt_h) {
	print "Options: -f(config file), -v(debug), -c(submit closed), -i(ignore lesser networks)\n";
	exit 0;
}
if($opt_f) {
	%config = ISSRT::ConConn::GetConfig($opt_f);
}else {
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


sub submit_ticket() {
	my $rttext = shift;
	my $subject = shift;
	my $constit = shift;
	
	my $status = "open";
	if($sclosed && ($constit eq "ResNet" || $constit eq "Tor")) {
		$status = "resolved";
	}
	
	unless($ignore && ($constit eq "ResNet" || $constit eq "Tor")) {	
		my $ticket = RT::Client::REST::Ticket->new(
			rt => $rt,
			queue => "Incidents",
			subject => $subject,
			status => $status,
			cf => {
				'Risk Severity' => 1,
				'_RTIR_Classification' => "Shadowserver",
				'_RTIR_Constituency' => $constit,
				'_RTIR_State' => $status,
			},
		)->store(text => $rttext);
		print "New ticket's id is ", $ticket->id, "\n" if($debug > 0);
	}
}	

sub find_c() {
	my $inip = shift;
	print("find_c inip was $inip\n") if($debug > 0);
	foreach my $net (@wirelessnets) {
		if(ipv4_in_network($net, $inip)) {
			return "Academic-Support";
		}
	}
	foreach my $net (@resnets) {
		if(ipv4_in_network($net, $inip)) {
			return "ResNet";
		}
	}
	foreach my $net (@tor) {
		if(ipv4_in_network($net, $inip)) {
			return "Tor";
		}
	}
	return "unclassified";
}

#checks if incident related to an ip has already been reported
sub matches_previous() {
	my $parent_id = shift;
	my $date = shift;
	my @attachments = $rt->get_attachment_ids(id => $parent_id);
	my $matches = 0;

	return 1 if $rt->show(type => 'ticket', id => $parent_id)->{"Subject"} =~ /$date/;

	for(@attachments) {
		my $attachment = $rt->get_attachment(parent_id => $parent_id, id => $_);
		$matches = 1 if($attachment->{"Content"} =~ /timestamp:.*$date/);
	}

	return $matches;
}

my ($type,$encoding,$disposition);
my $zipped = "";
while(<>) {
	$type = $1 if /Content-Type:.*(application)/;
	$encoding = $1 if /Content-Transfer-Encoding:.*(base64)/;
	$disposition = $1 if /Content-Disposition:.*(attachment)/;
	if($type && $encoding && $disposition) {
		chomp($zipped .= $_) if /^[0-9A-z\+\/]+$/;
	}
}

my $decoded = decode_base64($zipped);

open(my $zipfile, '<', \$decoded);
my $unzip = new IO::Uncompress::Unzip $zipfile or die "unzip failed: $UnzipError\n";

my $report = "";
until($unzip->eof) {
	$report .= $unzip->getline;
}

print $report if $debug > 0;
my $io = IO::String->new($report);

#parse the csv
my $csv = Text::CSV->new ({binary => 1}) or die "Cannot use CSV: ".Text::CSV->error_diag();
$csv->column_names($csv->getline($io));
my $incidents = $csv->getline_hr_all($io);

$rt = RT::Client::REST->new(
	server => 'https://' . $config{hostname},
	timeout => 30,
);

try {
	$rt->login(username => $config{username}, password => $config{password});
}catch Exception::Class::Base with {
	die "problem logging in: ", shift->message;
};

#deal with each incident in the csv
for my $incident (@$incidents) {
	my $ip = $incident->{"ip"};
	my $rttext;
	my $date = $incident->{"timestamp"};
	my $subject = "Shadowserver Report $ip $date";
	my $constit = &find_c($ip);
	my $qstring = qq|
	Queue = 'Incidents'
	AND Subject LIKE '%Shadowserver%$ip%'|;

	my @matches = $rt->search(
		type => 'ticket',
		query => $qstring,
	);

	for(keys %$incident) {
		$rttext .= "$_: ".$incident->{$_}."\n";
	}

	if(@matches) {
		unless(&matches_previous($matches[0], $date)){
			$rt->comment(
				ticket_id => shift @matches,
				message => $rttext,
			);
		}
	}else {
		&submit_ticket($rttext, $subject, $constit);
	}
}

