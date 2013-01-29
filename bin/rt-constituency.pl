#!/usr/bin/env perl -w

#IST-ISS Co-op Cheng Jie Shi <cjshi@uwaterloo.ca> Jan 2013
#Supervisor: Mike Patterson <mike.patterson@uwaterloo.ca>

use strict;
use warnings;
use vars qw/ $opt_c $opt_s $opt_e $opt_d $opt_v/;
use Getopt::Std;

my $start_run = time();
getopts('c:s:e:dv');

#-s -e time options
my (@output,%hash);
if($opt_s && $opt_e){
   @output = `rt-weeklyrep.pl $opt_s $opt_e `;
}elsif($opt_s){
   @output = `rt-weeklyrep.pl $opt_s`;
}elsif((!$opt_s)&&(!$opt_e)){
   @output = `rt-weeklyrep.pl`;
}

#print header
my $firstline = shift(@output);
print $opt_c." ";
print $firstline."\n";
print "Counts"."\t". "Classification"."\n";

#print summary
foreach my $line (@output){
   chomp($line);
   my @cur = split(/,/, $line); 
   my $classifi = $cur[2];
   my $consti = $cur[3];
   $consti =~ s/\"(.*)\"/$1/;
   if ($consti eq $opt_c){
      $classifi =~ s/\"(.*)\"/$1/;
      $hash{$classifi}++;
   }
}  
foreach my $key (keys %hash){
  if ($hash{$key} >= 1){
    print "$hash{$key}"."\t"."$key\n";
    }
}

#-v option
if($opt_v){
   #print title fields
   print "\n";
   my $secondline = shift(@output);
   chomp($secondline);
   my @curr = split(/,/, $secondline); 
   my $rt_number = $curr[0];
   $rt_number =~ s/\"(.*)\"/$1/;
   my $date = $curr[1];
   $date =~ s/\"(.*)\"/$1/;
   my $classification = $curr[2];
   $classification =~ s/^"//;
   $classification =~ s/"$//;
   my $subject = $curr[4];
   $subject =~ s/\"(.*)\"/$1/;
   printf "%-20s %-30s %-35s\n",
            $rt_number, $date, $classification;   

   #print details            
   foreach my $line (@output){
   chomp($line);
   my @currline = split(/","/, $line);
   my $cons = $currline[3];
   if ($cons eq $opt_c){
      my $rt_num = $currline[0];
      $rt_num =~ s/^"//;
      my $d = $currline[1];
      my $class = $currline[2];
      my $sub = $currline[4];
      $sub =~ s/"$//;
      printf "%-20s %-30s %-35s\n",
            $rt_num, $d, $class;
      print $sub."\n"."\n";       
   }
  }
}

#-d option
my $end_run = time();
if($opt_d){
  my $run_time = $end_run - $start_run;   
  print  "Query took $run_time seconds\n"; 
}