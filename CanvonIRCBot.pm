package CanvonIRCBot;
use Bot::BasicBot;
our @ISA = qw(Bot::BasicBot);

use strict;
use warnings;

#use Carp;
use FileHandle;
use Fcntl qw(:DEFAULT :seek);

# Get or set debugging state of the bot.
sub debug
{
    my $bot = shift(@_);

    $bot->{debug} = shift(@_) if (@_);

    my $debug = 0;
    $debug = $bot->{debug} if exists($bot->{debug});
    return $debug;
}

sub log_debug
{
    my $bot = shift(@_);

    $bot->log(@_) if $bot->debug();
}

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

    die("No Nagios log channels defined!\n")
      unless (exists($bot->{nagios_channels}) &&
              defined($bot->{nagios_channels}) &&
              @{$bot->{nagios_channels}} >= 1);

    my $nagios_logfile = $bot->get_nagios_logfile();

    $bot->log_debug("Opening Nagios log file: $nagios_logfile");
    open(my $fh, '<', $nagios_logfile) or die("Can't open Nagios log file $nagios_logfile: $!\n");

    # Put the file handle into the bot state.
    $bot->{nagios_logfile_fh} = $fh;

    # Seek to EOF, for later waiting for more log lines to appear.
    $bot->log_debug("Seeking to end of Nagios log file...");
    $fh->seek(0, SEEK_END) or die("Can't seek to end of Nagios log file: $!\n");

    # Set non-blocking IO.
    $bot->log_debug("Setting Nagios log file file handle to non-blocking IO...");
    $fh->blocking(0) or die("Can't set Nagios log file file handle to non-blocking IO: $!\n");

    # Everything went well so far.
    $bot->log_debug("Init succeeded.");
    return 1;
}

sub tick
{
    my ($bot) = @_;

    my $next_tick_secs = 1;

    my $fh = $bot->{nagios_logfile_fh};
    unless ($fh)
    {
        $bot->log("Couldn't get Nagios log file file handle!");
        return $next_tick_secs;
    }

    # Try to read a log line.
    my $line = <$fh>;
    if (defined($line))
    {
        chomp($line);

        # Got a log line, pass it on to the configured channels.
        $bot->log_debug("Got a Nagios log message, passing it on to configured channels...");
        foreach my $channel (@{$bot->{nagios_channels}})
        {
            $bot->log_debug("Passing to $channel: $line");

            # For now, simply send the whole line, unchecked and unformatted.
            $bot->say(channel => $channel, body => $line);
        }
    }

    # Periodically check again.
    return $next_tick_secs;
}

1;
