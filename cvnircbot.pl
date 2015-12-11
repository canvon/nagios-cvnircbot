#!/usr/bin/perl

use strict;
use warnings;

use CanvonIRCBot;

my $conffile = "$ENV{HOME}/.cvnircbot/cvnircbotrc";
my $config;

(my $basename = $0) =~ s#/.*/##;

unless ($config = do $conffile) {
    die "$basename: couldn't parse $conffile: $@\n" if $@;
    die "$basename: couldn't do $conffile: $!\n"    unless defined $config;
    die "$basename: couldn't run $conffile\n"       unless $config;
}

use Data::Dumper;
print(Dumper($config));
exit(0);
