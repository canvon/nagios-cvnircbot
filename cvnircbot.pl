#!/usr/bin/perl

use strict;
use warnings;

use CanvonIRCBot;

my $conffile = "$ENV{HOME}/.cvnircbot/cvnircbotrc";
my $config;

(my $basename = $0) =~ s#/.*/##;

while (scalar(@ARGV) > 0) {
    my $arg = shift;
    if ($arg !~ /^-/) {
        unshift(@ARGV, $arg);
        last;
    }

    if ($arg =~ /^(-\?|-h|--help|--usage)$/) {
        print("Usage: $basename [--config-file=CONFFILE]\n");
        exit(0);
    }
    elsif ($arg =~ /^--config-file=(.*)$/) {
        $conffile = $1;
    }
    else {
        die("$basename: Invalid argument \"$arg\"\n");
    }
}

scalar(@ARGV) == 0 or die("$basename: Invalid arguments\n");

unless ($config = do $conffile) {
    die "$basename: couldn't parse $conffile: $@\n" if $@;
    die "$basename: couldn't do $conffile: $!\n"    unless defined $config;
    die "$basename: couldn't run $conffile\n"       unless $config;
}

my $bot = CanvonIRCBot->new(@$config);
$bot->run();
