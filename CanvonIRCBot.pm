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

    $bot->{nagios_msg_ignore_external_command} = [
        'PROCESS_HOST_CHECK_RESULT',
        'PROCESS_SERVICE_CHECK_RESULT'
    ];
    $bot->{nagios_msg_ignore} = [
        'PASSIVE HOST CHECK',
        'PASSIVE SERVICE CHECK'
    ];

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

sub is_nagios_log_line_ignored
{
    my ($bot, $msg) = @_;
    return 1 if ((grep {$msg->{type} eq $_} (@{$bot->{nagios_msg_ignore}})) > 0);
    return 1 if ($msg->{type} eq 'EXTERNAL COMMAND' &&
                 (grep {$msg->{all_data}[0] eq $_} (@{$bot->{nagios_msg_ignore_external_command}})) > 0);
    return 0;
}

sub parse_nagios_log_line
{
    my ($bot, $line) = @_;
    my $ret = undef;

    unless ($line =~ /^\[([0-9]+)\] (.*)$/)
    {
        $bot->log("Couldn't parse Nagios log line into time stamp and rest.");
        return $ret;
    }

    my ($timestamp, $rest) = ($1, $2);
    $ret = {};
    $ret->{timestamp} = $timestamp;
    $ret->{full_msg} = $rest;
    $ret->{is_data} = 0;

    unless ($rest =~ /^([^:]*): (.*)$/)
    {
        $bot->log_debug("Non-data Nagios message ("
                       .localtime($ret->{timestamp})
                       ."): ".$ret->{full_msg});
        return $ret;
    }

    my ($type, $raw_data) = ($1, $2);
    $ret->{is_data} = 1;
    $ret->{type} = $type;
    $ret->{type_recognized} = 0;
    $ret->{raw_data} = $raw_data;

    my @all_data = split(/;/, $raw_data);
    $ret->{all_data} = [];
    @{$ret->{all_data}} = @all_data;

    if ($ret->{type} eq 'HOST ALERT')
    {
        $ret->{data} = {};
        $ret->{data}{HOSTNAME}         = $all_data[0];
        $ret->{data}{HOSTSTATE}        = $all_data[1];
        $ret->{data}{HOSTSTATETYPE}    = $all_data[2];
        $ret->{data}{HOSTATTEMPT}      = $all_data[3];
        $ret->{data}{HOSTOUTPUT}       = $all_data[4];
        $ret->{type_recognized} = 1
    }
    elsif ($ret->{type} eq 'SERVICE ALERT')
    {
        $ret->{data} = {};
        $ret->{data}{HOSTNAME}         = $all_data[0];
        $ret->{data}{SERVICEDESC}      = $all_data[1];
        $ret->{data}{SERVICESTATE}     = $all_data[2];
        $ret->{data}{SERVICESTATETYPE} = $all_data[3];
        $ret->{data}{SERVICEATTEMPT}   = $all_data[4];
        $ret->{data}{SERVICEOUTPUT}    = $all_data[5];
        $ret->{type_recognized}        = 1
    }
    elsif ($ret->{type} eq 'HOST NOTIFICATION')
    {
        $ret->{data} = {};
        $ret->{data}{CONTACTNAME}      = $all_data[0];
        $ret->{data}{HOSTNAME}         = $all_data[1];
        $ret->{data}{HOSTSTATE}        = $all_data[2];
        $ret->{data}{notify_command}   = $all_data[3];
        $ret->{data}{HOSTOUTPUT}       = $all_data[4];
        $ret->{type_recognized} = 1
    }
    elsif ($ret->{type} eq 'SERVICE NOTIFICATION')
    {
        $ret->{data} = {};
        $ret->{data}{CONTACTNAME}      = $all_data[0];
        $ret->{data}{HOSTNAME}         = $all_data[1];
        $ret->{data}{SERVICEDESC}      = $all_data[2];
        $ret->{data}{SERVICESTATE}     = $all_data[3];
        $ret->{data}{notify_command}   = $all_data[4];
        $ret->{data}{SERVICEOUTPUT}    = $all_data[5];
        $ret->{type_recognized} = 1
    }

    unless ($ret->{type_recognized} || $bot->is_nagios_log_line_ignored($ret))
    {
        $bot->log_debug("Unrecognized data Nagios message ("
                       .localtime($ret->{timestamp})
                       ."): type=\"".$ret->{type}."\", raw data: "
                       .$ret->{raw_data});
    }
    #else
    #{
    #    $bot->log_debug("Recognized data Nagios message ("
    #                   .localtime($ret->{timestamp})
    #                   ."): type=\"".$ret->{type}."\", data hash entries: "
    #                   .scalar(keys %{$ret->{data}}));
    #}

    return $ret;
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

        my $msg = $bot->parse_nagios_log_line($line);
        unless (defined($msg))
        {
            $bot->log("Couldn't parse Nagios log line: $line");
            return $next_tick_secs;
        }

        if ($bot->is_nagios_log_line_ignored($msg))
        {
            # Silently ignore, or else the log spam will make us go crazy...
            return $next_tick_secs;
        }

        # Got a log line, pass it on to the configured channels.
        $bot->log_debug("Got a Nagios log message, passing it on to configured channels...");
        foreach my $channel (@{$bot->{nagios_channels}})
        {
            my $out = '';
            my $out_public = 0;

            if ($msg->{is_data} && $msg->{type_recognized})
            {
                if ($msg->{type} eq 'HOST NOTIFICATION')
                {
                    $out .= $msg->{data}{CONTACTNAME}.": ** Host Alert: " .
                            $msg->{data}{HOSTNAME}." is ".
                            $msg->{data}{HOSTSTATE}." **  ".
                            "Info: ".$msg->{data}{HOSTOUTPUT}."  ".
                            "Date/Time: ".localtime($msg->{timestamp});
                    $out_public = 1;
                }
                elsif ($msg->{type} eq 'SERVICE NOTIFICATION')
                {
                    $out .= $msg->{data}{CONTACTNAME}.": ** Service Alert: " .
                            $msg->{data}{HOSTNAME}."/".
                            $msg->{data}{SERVICEDESC}." is ".
                            $msg->{data}{SERVICESTATE}." **  ".
                            "Info: ".$msg->{data}{SERVICEOUTPUT}."  ".
                            "Date/Time: ".localtime($msg->{timestamp});
                    $out_public = 1;
                }
                elsif ($msg->{type} eq 'HOST ALERT')
                {
                    $out .= "host alert: ".$msg->{data}{HOSTNAME}.
                            " is ".$msg->{data}{HOSTSTATE}.
                            ", type ".$msg->{data}{HOSTSTATETYPE}.
                            " (".$msg->{data}{HOSTATTEMPT}.
                            "):  Info: ".$msg->{data}{HOSTOUTPUT}.
                            "  Date/Time: ".localtime($msg->{timestamp});
                }
                elsif ($msg->{type} eq 'SERVICE ALERT')
                {
                    $out .= "service alert: ".$msg->{data}{HOSTNAME}.
                            "/".$msg->{data}{SERVICEDESC}.
                            " is ".$msg->{data}{SERVICESTATE}.
                            ", type ".$msg->{data}{SERVICESTATETYPE}.
                            " (".$msg->{data}{SERVICEATTEMPT}.
                            "):  Info: ".$msg->{data}{SERVICEOUTPUT}.
                            "  Date/Time: ".localtime($msg->{timestamp});
                }
            }
            else
            {
                $bot->log_debug("Not passing unknown/unwanted message on: $line");
            }

            # Send the constructed line to the channel.
            # (But only if it has in fact been constructed.)
            if (length($out) >= 1)
            {
                $bot->log_debug("Passing to $channel: $out");
                if ($out_public)
                {
                    $bot->say(channel => $channel, body => $out);
                }
                else
                {
                    $bot->notice(channel => $channel, body => $out);
                }
            }
        }
    }

    # Periodically check again.
    return $next_tick_secs;
}

sub said
{
    my ($bot, $irc_msg) = @_;

    # Say nothing unless we were addressed.
    return undef unless $irc_msg->{address};

    $bot->log_debug("We were addressed! ".$irc_msg->{who}." said to us: ".$irc_msg->{body});

    for ($irc_msg->{body})
    {
        if (/^problems$/)
        {
            my $result = `icli -C -xn -z'!o'`;
            foreach my $line (split(/\n/, $result))
            {
                next unless (length($line) >= 1);

                # For now, simply pass on the icli output lines unmodified,
                # and with no output size limiting...
                $irc_msg->{body} = $line;
                $bot->say(%{$irc_msg});
            }

            return undef;
        }
        else
        {
            $bot->log_debug("Unknown command `$_'.");
            return "Unknown command.";
        }
    }

    # Say nothing, if we should get here.
    $bot->log_debug("Saying nothing as fallback.");
    return undef;
}

1;
