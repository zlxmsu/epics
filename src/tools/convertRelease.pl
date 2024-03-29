eval 'exec perl -S $0 ${1+"$@"}'  # -*- Mode: perl -*-
    if $running_under_some_shell; # convertRelease.pl
#*************************************************************************
# Copyright (c) 2008 UChicago Argonne LLC, as Operator of Argonne
#     National Laboratory.
# Copyright (c) 2002 The Regents of the University of California, as
#     Operator of Los Alamos National Laboratory.
# EPICS BASE is distributed subject to a Software License Agreement found
# in file LICENSE that is included with this distribution. 
#*************************************************************************
#
# Revision-Id: anj@aps.anl.gov-20110713153813-utpd5swcmji6ce4l
#
# Convert configure/RELEASE file(s) into something else.
#

use strict;

use FindBin qw($Bin);
use lib ("$Bin/../../lib/perl", $Bin);

use Cwd qw(cwd);
use Getopt::Std;
use EPICS::Path;
use EPICS::Release;

use vars qw($arch $top $iocroot $root);

our ($opt_a, $opt_t, $opt_T);

$Getopt::Std::OUTPUT_HELP_VERSION = 1;
getopts('a:t:T:') or &HELP_MESSAGE;

my $cwd = UnixPath(cwd());

if ($opt_a) {
    $arch = $opt_a;
} else {                # Look for O.<arch> in current path
    $cwd =~ m{ / O. ([\w-]+) $}x;
    $arch = $1;
}

if ($opt_T) {
    $top = $opt_T;
} else {                # Find $top from current path
    # This approach only works inside iocBoot/* and configure/*
    $top = $cwd;
    $top =~ s{ / iocBoot .* $}{}x;
    $top =~ s{ / configure .* $}{}x;
}

# The IOC may need a different path to get to $top
if ($opt_t) {
    $iocroot = $opt_t;
    $root = $top;
    while (substr($iocroot, -1, 1) eq substr($root, -1, 1)) {
        chop $iocroot;
        chop $root;
    }
}

&HELP_MESSAGE unless @ARGV == 1;

my $outfile = $ARGV[0];

# TOP refers to this application
my %macros = (TOP => LocalPath($top));
my @apps   = ('TOP');   # Records the order of definitions in RELEASE file

# Read the RELEASE file(s)
my $relfile = "$top/configure/RELEASE";
die "Can't find $relfile" unless (-f $relfile);
readReleaseFiles($relfile, \%macros, \@apps, $arch);
expandRelease(\%macros, \@apps);


# This is a perl switch statement:
for ($outfile) {
    m/releaseTops/       and do { &releaseTops;         last; };
    m/dllPath\.bat/      and do { &dllPath;             last; };
    m/cdCommands/        and do { &cdCommands;          last; };
    m/envPaths/          and do { &envPaths;            last; };
    m/checkRelease/      and do { &checkRelease;        last; };
    die "Output file type \'$outfile\' not supported";
}


############### Subroutines only below here ###############

sub HELP_MESSAGE {
    print STDERR <<EOF;
Usage: convertRelease.pl [-a arch] [-T top] [-t ioctop] outfile
    where outfile is one of:
        releaseTops - lists the module names defined in RELEASE*s
        dllPath.bat - path changes for cmd.exe to find WIN32 DLLs
        cdCommands - generate cd path strings for vxWorks IOCs
        envPaths - generate epicsEnvSet commands for other IOCs
        checkRelease - checks consistency with support modules
EOF
    exit 2;
}

#
# List the module names defined in RELEASE* files
#
sub releaseTops {
    my @includes = grep !m/^ (TOP | TEMPLATE_TOP) $/x, @apps;
    print join(' ', @includes), "\n";
}

#
# Generate Path files so Windows can find our DLLs
#
sub dllPath {
    unlink $outfile;
    open(OUT, ">$outfile") or die "$! creating $outfile";
    print OUT "\@ECHO OFF\n";
    print OUT "PATH %PATH%;", join(';', binDirs()), "\n";
    close OUT;
}

sub binDirs {
    my @includes = grep !m/^ (RULES | TEMPLATE_TOP) $/x, @apps;
    my @path;
    foreach my $app (@includes) {
        my $path = $macros{$app} . "/bin/$arch";
        next unless -d $path;
        $path =~ s/^$root/$iocroot/o if ($opt_t);
        push @path, LocalPath($path);
    }
    return @path;
}

#
# Generate cdCommands file with cd path strings for vxWorks IOCs and
# RTEMS IOCs using CEXP (need parentheses around command arguments).
#
sub cdCommands {
    die "Architecture not set (use -a option)" unless ($arch);
    my @includes = grep !m/^(RULES | TEMPLATE_TOP)$/x, @apps;
    
    unlink($outfile);
    open(OUT,">$outfile") or die "$! creating $outfile";
    
    my $startup = $cwd;
    $startup =~ s/^$root/$iocroot/o if ($opt_t);
    $startup =~ s/([\\"])/\\\1/g; # escape back-slashes and double-quotes
    
    print OUT "startup = \"$startup\"\n";
    
    my $ioc = $cwd;
    $ioc =~ s/^.*\///;  # iocname is last component of directory name
    
    print OUT "putenv(\"ARCH=$arch\")\n";
    print OUT "putenv(\"IOC=$ioc\")\n";
    
    foreach my $app (@includes) {
        my $iocpath = my $path = $macros{$app};
        $iocpath =~ s/^$root/$iocroot/o if ($opt_t);
        $iocpath =~ s/([\\"])/\\\1/g; # escape back-slashes and double-quotes
        my $app_lc = lc($app);
        print OUT "$app_lc = \"$iocpath\"\n"
            if (-d $path);
        print OUT "putenv(\"$app=$iocpath\")\n"
            if (-d $path);
        print OUT "${app_lc}bin = \"$iocpath/bin/$arch\"\n"
            if (-d "$path/bin/$arch");
    }
    close OUT;
}

#
# Generate envPaths file with epicsEnvSet commands for iocsh IOCs.
# Include parentheses anyway in case CEXP users want to use this.
#
sub envPaths {
    die "Architecture not set (use -a option)" unless ($arch);
    my @includes = grep !m/^ (RULES | TEMPLATE_TOP) $/x, @apps;
    
    unlink($outfile);
    open(OUT,">$outfile") or die "$! creating $outfile";
    
    my $ioc = $cwd;
    $ioc =~ s/^.*\///;  # iocname is last component of directory name
    
    print OUT "epicsEnvSet(\"ARCH\",\"$arch\")\n";
    print OUT "epicsEnvSet(\"IOC\",\"$ioc\")\n";
    
    foreach my $app (@includes) {
        my $iocpath = my $path = $macros{$app};
        $iocpath =~ s/^$root/$iocroot/o if ($opt_t);
        $iocpath =~ s/([\\"])/\\\1/g; # escape back-slashes and double-quotes
        print OUT "epicsEnvSet(\"$app\",\"$iocpath\")\n" if (-d $path);
    }
    close OUT;
}

#
# Check RELEASE file consistency with support modules
#
sub checkRelease {
    my $status = 0;
    delete $macros{RULES};
    delete $macros{TOP};
    delete $macros{TEMPLATE_TOP};
    
    while (my ($app, $path) = each %macros) {
        my %check = (TOP => $path);
        my @order = ();
        my $relfile = "$path/configure/RELEASE";
        readReleaseFiles($relfile, \%check, \@order, $arch);
        expandRelease(\%check, \@order);
        delete $check{TOP};
        delete $check{EPICS_HOST_ARCH};
        
        while (my ($parent, $ppath) = each %check) {
            if (exists $macros{$parent} &&
                AbsPath($macros{$parent}) ne AbsPath($ppath)) {
                print "\n" unless ($status);
                print "Definition of $parent conflicts with $app support.\n";
                print "In this application a RELEASE file defines\n";
                print "\t$parent = $macros{$parent}\n";
                print "but $app at $path defines\n";
                print "\t$parent = $ppath\n";
                $status = 1;
            }
        }
    }
    print "\n" if ($status);
    exit $status;
}

