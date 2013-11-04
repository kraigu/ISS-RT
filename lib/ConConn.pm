package ISSRT::ConConn;

our @EXPORT_OK = qw(GetConfig config);

use strict;
use warnings;

use Config::General;
use Data::Dumper;
use Net::IPv4Addr qw( :all );

my $debug = 0;

my (@wirelessnets, @resnets, @tor) = ();

sub GetConfig{
	my $configfile = qq|$ENV{"HOME"}/.rtrc|;
	if($_[0]) {
		$configfile = $_[0];
	}
	if( ! -e $configfile){ 
		die "\n$configfile does not exist\n";
	}
	my $perms = sprintf("%o",(stat($configfile))[2] & 07777);
	if($debug > 3){ print "Permissions on rc file: " . Dumper($perms); }
	die "\nConfig file must not have any more than owner rw\n"
		unless ($perms == '600' || $perms == '0400');

	my $conf = new Config::General($configfile);
	my %config = $conf->getall;
	if($debug > 3){ print "Config is: \n" . Dumper(\%config) . "\n"; }

	die "\nNo password!\n" unless $config{password};
	die "\nNo hostname!\n" unless $config{hostname};
	die "\nNo username!\n" unless $config{username};
	die "\nNo wireless networks!\n" unless $config{wireless};
	die "\nNo resnet!\n" unless $config{resnet};

	push(@wirelessnets, &deref($config{"wireless"}));
	push(@resnets, &deref($config{"resnet"}));
	push(@tor, &deref($config{"tor"}));

	return %config;
}

sub getSID{
	my $configfile = qq|$ENV{"HOME"}/ExceptionSID|;
	if($_[0]) {
		$configfile = $_[0];
	}
	if( ! -e $configfile){ 
		die "\n$configfile does not exist\n";
	}
	my $perms = sprintf("%o",(stat($configfile))[2] & 07777);
	if($debug > 3){ print "Permissions on rc file: " . Dumper($perms); }
	die "\nConfig file must not have any more than owner rw\n"
		unless ($perms == '600' || $perms == '0400');
        open(FILE, $configfile);
        my @output =<FILE>;
        return @output;
}

sub deref{
	my $value = shift;
	if(ref($value) eq "ARRAY"){
		return @{$value};
	}
	return $value;
}

sub getConstituency{
	my $inip = shift;
	print("initial ip was $inip\n") if($debug > 0);
	foreach my $net (@wirelessnets){
		if(ipv4_in_network($net, $inip)){
			return "Wireless";
		}
	}
	foreach my $net (@resnets){
		if(ipv4_in_network($net, $inip)){
			return "ResNet";
		}
	}
	foreach my $net (@tor){
		if(ipv4_in_network($net, $inip)){
			return "Tor";
		}
	}
	return "unclassified";
}

1;
