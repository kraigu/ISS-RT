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
use vars qw/$opt_f $opt_v $opt_h $opt_i $opt_t $opt_o/;
use Getopt::Std;
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use MIME::Base64;
use Data::Dumper;
use LWP::UserAgent;

getopts('f:v:hit:o:');

my $rt;

my $debug = $opt_v || 0;
my $ignore = $opt_i || 0;
my %config;

my $mailsubject = "No subject";

if($opt_h) {
	print "Options: -f(config file), -v(verbose/debug), -i(ignore wireless/resnet networks) -t(timeout)\n";
	print "-o (output file for debugging, implies -v 1000)\n"; #probably should just redirect STDERR/STDOUT?
	exit 0;
}
if($opt_f) {
	%config = ISSRT::ConConn::GetConfig($opt_f);
}else {
	%config = ISSRT::ConConn::GetConfig();
}

if($opt_o) {
	$opt_v = 1000;
	open(OUTPUTFILE, ">>", "$opt_o") || die "Cannot open output file: $!";
}

#configure the Waterloo specific networks
my (@wirelessnets, @resnets, @tor) = ();
my $value = $config{"wireless"};
if(ref($value) eq "ARRAY") {
	@wirelessnets = @{$value};
} else {
	push(@wirelessnets, $value);
}
$value = $config{"resnet"};
if(ref($value) eq "ARRAY") {
	@resnets = @{$value};
} else {
	push(@resnets, $value);
}
$value = $config{"tor"};
if(ref($value) eq "ARRAY") {
	@tor = @{$value};
} else {
	push(@tor, $value);
}

sub submit_ticket {
	my $rttext = shift;
	my $subject = shift;
	my $constit = shift;
	
	unless($ignore && ($constit eq "ResNet" || $constit eq "Wireless")) {	
		my $ticket = RT::Client::REST::Ticket->new(
			rt => $rt,
			queue => "Incident Reports",
			subject => $subject,
			cf => {
				'_RTIR_Constituency' => $constit,
			},
		)->store(text => $rttext);
		print "New ticket's id is ", $ticket->id, "\n" if($debug > 0);
	}
}	

sub find_c {
	my $inip = shift;
	print("find_c inip was $inip\n") if($debug > 0);
	foreach my $net (@wirelessnets) {
		if(ipv4_in_network($net, $inip)) {
			return "Wireless";
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

### begin main body

my ($type,$encoding,$disposition);
my $zipped = "";
my $insubject = 0;
while(<>) {
	if($opt_o){
		print OUTPUTFILE "$_";
	}
	if(/^\w:/ || /^$/) {
		$insubject = 0;
	}
	if($insubject) {
		$mailsubject .= $_;
	}
	if (/^(Subject:)(.*)/){
		$mailsubject = $2;
		$insubject = 1;
	}
	$type = $1 if /Content-Type:.*(application)/;
	$encoding = $1 if /Content-Transfer-Encoding:.*(base64)/;
	$disposition = $1 if /Content-Disposition:.*(attachment)/;
	if($type && $encoding && $disposition) {
		chomp($zipped .= $_) if /^[0-9A-z\+\/=]+$/;
	}
}

# trim whitespace
$mailsubject =~ s/^\s+//;
$mailsubject =~ s/\s+$//;
if($opt_o) {
	print OUTPUTFILE "SUBJECT FOUND: $mailsubject\n";
}

my $decoded = decode_base64($zipped);

open(my $zipfile, '<', \$decoded);
my $unzip = new IO::Uncompress::Unzip $zipfile or die "unzip failed: $UnzipError\n";

my $report = "";
until($unzip->eof) {
	$report .= $unzip->getline;
}

if($opt_o){
	print OUTPUTFILE "\n$report\n";
}
my $io = IO::String->new($report);

#parse the csv
my $csv = Text::CSV->new ({binary => 1}) or die "Cannot use CSV: ".Text::CSV->error_diag();
$csv->column_names($csv->getline($io));
my $incidents = $csv->getline_hr_all($io);

$rt = RT::Client::REST->new(
	server => 'https://' . $config{hostname},
	timeout => $opt_t || 30,
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
	my $subject = "$mailsubject $ip $date";
	my $constit = &find_c($ip);

	# We never want to put Tor incidents into our database.
	next if $constit eq "Tor";

	for(keys %$incident) {
		$rttext .= "$_: ".$incident->{$_}."\n";
	}
	&submit_ticket($rttext, $subject, $constit);
}

if($opt_o){
	close(OUTPUTFILE);
}
