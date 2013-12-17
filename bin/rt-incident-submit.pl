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
use Scalar::Util qw(looks_like_number);
use Getopt::Long;

my ($opt_s, $opt_i, $opt_p, $opt_f, $opt_v, $opt_h, $opt_cl, $opt_co, $opt_r, $classification, $constituency);
my $queue = 'Incidents';

GetOptions ("s=s" => \$opt_s,
            "i=s" => \$opt_i, 
            "p=s" => \$opt_p, 
            "f=s" => \$opt_f, 
            "v=s" => \$opt_v, 
            "cl=s" => \$opt_cl, 
            "co=s" => \$opt_co,
            "r" => \$opt_r,
            "h" => \$opt_h,       
);  
            
my $debug = $opt_v || 0;
my %config;

if($opt_h){
  print <<EOH;
$0 options:
\t-s subject (required)
\t-i file name (required)
\t-p priority (optional, defaults to 3)
\t-f config file (optional, defaults to ~/.rtrc)
\t-cl classification (optional)
\t-co constituency (optional)
\t-r submit an incident report instead of an incident (optional)
\t-v verbosity
EOH
  exit 0;
}
if($opt_f){
	%config = ISSRT::ConConn::GetConfig($opt_f);
} else {
	%config = ISSRT::ConConn::GetConfig();
}
my $subject = $opt_s || die "Need a subject\n";
my $infilename = $opt_i || die "Need a file name\n";
my $pri;
if($pri = $opt_p){
	die "Priority must be a digit (1-5)\n" unless looks_like_number($pri);
} else {
	$pri = 3;
}
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

# set bogus values for classification/constituency to be fixed later
# unless they're set on the command line
$classification =  $opt_cl || '';
$constituency =   $opt_co || 'EDUNET';

$queue = 'Incident Reports' if($opt_r);

my $ticket = RT::Client::REST::Ticket->new(
	rt => $rt,
	queue => $queue,
	subject => $subject,
	cf => {
		'Risk Severity' => $pri,
		'_RTIR_Classification' => $classification,
		'_RTIR_Constituency' => $constituency
	},	
)->store(text => $rttext);
print "New ticket's ID is ", $ticket->id, "\n";
