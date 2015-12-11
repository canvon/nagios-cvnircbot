package CanvonIRCBot;
use Bot::BasicBot;
our @ISA = qw(Bot::BasicBot);

use strict;
use warnings;

#use Carp;
use FileHandle;
use Fcntl qw(:DEFAULT :seek);

sub get_nagios_logfile
{
    my ($bot) = @_;

    die("Nagios log file location not configured!\n") unless exists($bot->{nagios_logfile});
    return "/var/log/nagios3/nagios.log" unless defined($bot->{nagios_logfile});
    return $bot->{nagios_logfile};
}

sub init
{
    my ($bot) = @_;

    my $nagios_logfile = $bot->get_nagios_logfile();

    open(my $fh, '<', $nagios_logfile) or die("Can't open Nagios log file $nagios_logfile: $!\n");

    # Put the file handle into the bot state.
    $bot->{nagios_logfile_fh} = $fh;

    # Seek to EOF, for later waiting for more log lines to appear.
    $fh->seek(0, SEEK_END);

    # Set non-blocking IO.
    $fh->blocking(0) or die("Can't set Nagios log file file handle to non-blocking IO: $!\n");

    # Everything went well so far.
    return 1;
}

1;
