#!/usr/bin/env perl
use strict;
use warnings;

# Print out full details on a given RT number

use FindBin;
use lib "$FindBin::Bin/../lib";

use Data::Dumper;
use Config::General;
use RT::Client::REST;
use Error qw|:try|;
use Date::Manip;
use ConConn;
use vars qw/$opt_s $opt_f $opt_h/;
use Getopt::Std;

getopts('s:f:h');
my %config;
my $ticket;

if($opt_h){
     print "Options: -s(Search string), -f(config file)\n";
}else{
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
my $t;
if($opt_s){
	$t = $opt_s;
} else {
	die "No search string given, specify an RT number with -s\n";
}

try {
	$ticket = $rt->show(type => 'ticket', id => $t);
} catch RT::Client::REST::UnauthorizedActionException with {
    print "You are not authorized to view ticket $t\n";
} catch RT::Client::REST::Exception with {
	print "DERP\n";
};

print Dumper($ticket);
}