#!/usr/bin/perl
#
# Tool to expand @VAR@ variables while copying a file.
# The file will *not* be copied if it already exists.
#
# Author: Andrew Johnson <anj@aps.anl.gov>
# Date: 10 February 2005
#
# Revision-Id: anj@aps.anl.gov-20101026142747-yfjkhakzmp4rnj0g
#

use strict;

use FindBin qw($Bin);
use lib ("$Bin/../../lib/perl", $Bin);

use EPICS::Getopts;
use EPICS::Path;
use EPICS::Release;
use EPICS::Copy;

# Process command line options
our ($opt_a, $opt_d, @opt_D, $opt_h, $opt_t);
getopts('a:dD@ht:')
    or &HELP_MESSAGE;

# Handle the -h command
&HELP_MESSAGE if $opt_h;

die "Path to TOP not set, use -t option\n"
    unless $opt_t;

# Check filename arguments
my $infile = shift
    or die "No input filename argument\n";
my $outfile = shift
    or die "No output filename argument\n";

# Where are we?
my $top = AbsPath($opt_t);
print "TOP = $top\n" if $opt_d;

# Read RELEASE file into vars
my %vars = (TOP => $top);
my @apps = ('TOP');
readReleaseFiles("$top/configure/RELEASE", \%vars, \@apps, $opt_a);
expandRelease(\%vars);

$vars{'ARCH'} = $opt_a if $opt_a;

while ($_ = shift @opt_D) {
    my ($var, $val) = split /=/;
    $vars{$var} = $val;
    print "$var = $val\n" if $opt_d;
}

# Do it!
copyFile($infile, $outfile, \%vars);

##### File contains subroutines only below here

sub HELP_MESSAGE {
    print STDERR <<EOF;
Usage:
    expandVars.pl -h
        Display this Usage message
    expandVars.pl -t /path/to/top [-a arch] -D var=val ... infile outfile
        Expand vars in infile to generate outfile
EOF
    exit $opt_h ? 0 : 1;
}
