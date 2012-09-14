#!/usr/bin/env perl

# 
use strict;
use warnings;

use Data::Dumper;
use Config::General;
use RT::Client::REST;
use RT::Client::REST::Ticket;
use Error qw|:try|;
use Date::Manip;

my $debug = 0;

my $configfile = qq|$ENV{"HOME"}/.rtrc|;

if( ! -e $configfile){ 
        die "\n$configfile does not exist\n";
}
my $perms = sprintf("%o",(stat($configfile))[2] & 07777);
if($debug > 1){ print Dumper($perms); }
die "\nConfig file must not have any more than owner rw\n"
        unless ($perms == '600' || $perms == '0400');

my $conf = new Config::General($configfile);
my %config = $conf->getall;
if($debug > 1){ print Dumper(\%config); }

die "\nNo password!\n" unless $config{password};
die "\nNo hostname!\n" unless $config{hostname};
die "\nNo username!\n" unless $config{username};

my $subject = $ARGV[0] || die "Need a subject\n";
my $infilename = $ARGV[1] || die "Need a file name\n";
$/ = undef; # we're going to want to read a whole file into a string
open(FILE,"$infilename") || die "Couldn't open file $infilename $!\n";
my $rttext = <FILE>;
close(FILE);

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
)->store(text => $rttext);
print "New ticket's ID is ", $ticket->id, "\n";

