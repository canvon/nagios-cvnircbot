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

    # $bot->log() will log every argument on a separate line,
    # so we'll have to prefix each argument separately.
    my @newargs = map { '<7>'.$_ } @_;
    $bot->log(@newargs) if $bot->debug();
}

sub log_info    { my $bot = shift(@_); my @newargs = map { '<6>'.$_ } @_; $bot->log(@newargs); }
sub log_notice  { my $bot = shift(@_); my @newargs = map { '<5>'.$_ } @_; $bot->log(@newargs); }
sub log_warning { my $bot = shift(@_); my @newargs = map { '<4>'.$_ } @_; $bot->log(@newargs); }
sub log_err     { my $bot = shift(@_); my @newargs = map { '<3>'.$_ } @_; $bot->log(@newargs); }
sub log_crit    { my $bot = shift(@_); my @newargs = map { '<2>'.$_ } @_; $bot->log(@newargs); }
sub log_alert   { my $bot = shift(@_); my @newargs = map { '<1>'.$_ } @_; $bot->log(@newargs); }
sub log_emerg   { my $bot = shift(@_); my @newargs = map { '<0>'.$_ } @_; $bot->log(@newargs); }

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

    # Have some warn()/die() handlers to present the situation better
    # to logging. In case of dying on error, also tell the fact to IRC.
    # (But don't tell the details to IRC! That might help someone
    # attacking the bot/system.)
    $SIG{__WARN__} = sub {
	    my $flag = 0;
	    my @newargs = map { my $str = $_; chomp($str); split(/\n/, $str) } @_;
	    $bot->log_warning(
		    map { ($flag++ ? "Warning continues: " : "Warning handler received warning: ").$_ } @newargs
	    );
    };
    $SIG{__DIE__} = sub {
	    my $flag = 0;
	    my @newargs = map { my $str = $_; chomp($str); split(/\n/, $str) } @_;
	    $bot->log_crit(
		    map { ($flag++ ? "Error continues: " : "Dying on error: ").$_ } @newargs
	    );
	    $bot->shutdown("Died on error!");
	    exit(1);
    };

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

    $bot->log_notice("Opening Nagios log file: $nagios_logfile");
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
    $bot->log_notice("Init succeeded.");
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
        $bot->log_warning("Couldn't parse Nagios log line into time stamp and rest.");
        $bot->log_warning("Log line was: \"".escape_nonprints($line)."\"");
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
                       ."): ".escape_nonprints($ret->{full_msg}));
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
                       .escape_nonprints($ret->{raw_data}));
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

sub colorize_hoststate
{
	my ($state) = @_;

	for ($state)
	{
		if    (/^UP$/)          { return "\x031,9$state\x0f"; }
		#elsif (/^WARNING$/)     { return "\x031,8$state\x0f"; }
		elsif (/^DOWN$/)        { return "\x030,4$state\x0f"; }
		elsif (/^UNREACHABLE$/) { return "\x030,12$state\x0f"; }
		else                    { return "\x030,14$state\x0f"; }
	}
}

sub colorize_servicestate
{
	my ($state) = @_;

	for ($state)
	{
		if    (/^OK$/)       { return "\x031,9$state\x0f"; }
		elsif (/^WARNING$/)  { return "\x031,8$state\x0f"; }
		elsif (/^CRITICAL$/) { return "\x030,4$state\x0f"; }
		elsif (/^UNKNOWN$/)  { return "\x030,12$state\x0f"; }
		else                 { return "\x030,14$state\x0f"; }
	}
}

sub colorize_datetime
{
	my ($datetime) = @_;

	return "\x0314$datetime\x0f";
}

sub escape_nonprints
{
	my ($str) = @_;

	$str =~ s/\\/\\\\/g;
	$str =~ s/([\x01-\x1a])/"^".chr(ord('A') - 1 + ord($1))/eg;
	$str =~ s/([\x00-\x1f\x7f-\xff])/"\\x".sprintf("%02x", ord($1))/eg;

	return $str;
}

sub tick
{
    my ($bot) = @_;

    my $next_tick_secs = 1;

    my $fh = $bot->{nagios_logfile_fh};
    unless ($fh)
    {
        $bot->log_err("Couldn't get Nagios log file file handle!");
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
            $bot->log_err("Couldn't parse Nagios log line: \"".escape_nonprints($line)."\"");
            return $next_tick_secs;
        }

        if ($bot->is_nagios_log_line_ignored($msg))
        {
            # Silently ignore, or else the log spam will make us go crazy...
            return $next_tick_secs;
        }

        # Got a log line, pass it on to the configured channels.
        $bot->log_info("Got a Nagios log message".
		" (is_data=".$msg->{is_data}.
		", type_recognized=".$msg->{type_recognized}.
		", type=\"".$msg->{type}."\")".
		", passing it on to configured channels...");
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
                            colorize_hoststate($msg->{data}{HOSTSTATE})." **  ".
                            "Info: ".$msg->{data}{HOSTOUTPUT}."  ".
                            colorize_datetime("Date/Time: ".localtime($msg->{timestamp}));
                    $out_public = 1;
                }
                elsif ($msg->{type} eq 'SERVICE NOTIFICATION')
                {
                    $out .= $msg->{data}{CONTACTNAME}.": ** Service Alert: " .
                            $msg->{data}{HOSTNAME}."/".
                            $msg->{data}{SERVICEDESC}." is ".
                            colorize_servicestate($msg->{data}{SERVICESTATE})." **  ".
                            "Info: ".$msg->{data}{SERVICEOUTPUT}."  ".
                            colorize_datetime("Date/Time: ".localtime($msg->{timestamp}));
                    $out_public = 1;
                }
                elsif ($msg->{type} eq 'HOST ALERT')
                {
                    $out .= "host alert: ".$msg->{data}{HOSTNAME}.
                            " is ".$msg->{data}{HOSTSTATE}.
                            ", type ".$msg->{data}{HOSTSTATETYPE}.
                            " (".$msg->{data}{HOSTATTEMPT}.
                            "):  Info: ".$msg->{data}{HOSTOUTPUT}.
                            "  ".colorize_datetime("Date/Time: ".localtime($msg->{timestamp}));
                }
                elsif ($msg->{type} eq 'SERVICE ALERT')
                {
                    $out .= "service alert: ".$msg->{data}{HOSTNAME}.
                            "/".$msg->{data}{SERVICEDESC}.
                            " is ".$msg->{data}{SERVICESTATE}.
                            ", type ".$msg->{data}{SERVICESTATETYPE}.
                            " (".$msg->{data}{SERVICEATTEMPT}.
                            "):  Info: ".$msg->{data}{SERVICEOUTPUT}.
                            "  ".colorize_datetime("Date/Time: ".localtime($msg->{timestamp}));
                }
            }
            else
            {
                $bot->log_info("Not passing unknown/unwanted message on: \"".escape_nonprints($line)."\"");
            }

            # Send the constructed line to the channel.
            # (But only if it has in fact been constructed.)
            if (length($out) >= 1)
            {
                $bot->log_debug("Passing to $channel: \"".escape_nonprints($out)."\"");
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

    my $pass_back = sub {
        my ($line) = @_;
        $bot->log_debug("Passing back line: \"".escape_nonprints($line)."\"");
        $irc_msg->{body} = $line;
        $bot->say(%{$irc_msg});
    };

    # Say nothing unless we were addressed.
    return undef unless $irc_msg->{address};

    $bot->log_debug("We were addressed! ".$irc_msg->{who}." said to us: \"".escape_nonprints($irc_msg->{body})."\"");

    for ($irc_msg->{body})
    {
        if (/^overview$/)
        {
            $bot->log_info("Request for command 'overview'; starting icli...");

            #my $result = `icli -C -xn -z'!o'`;
            my $result = `icli -v -C -xn -o`;
            my $oline_accum = '';
            my $is_firstline = 1;
            my $type;
            foreach my $line (split(/\n/, $result))
            {
                if (length($line) == 0) {
                    $pass_back->($oline_accum) unless length($oline_accum) == 0;
                    $oline_accum = '';
                    $is_firstline = 1;
                    next;
                }

                if ($is_firstline) {
                    return "Error parsing backend output! Total not found in first line."
                      unless ($line =~ /^total\s+([a-z]+)\s+([0-9]+)$/);
                    my $count;
                    ($type, $count) = ($1, $2);

                    $oline_accum = "Total $count $type:";
                    $is_firstline = 0;
                    next;
                }

                return "Error parsing backend output! Can't handle normal line..."
                  unless ($line =~ /^([a-z]+)\s+([0-9]+)?$/);
                my ($state, $count) = ($1, $2);

                if (defined($count)) {
                    $state =~ s/^(.*)$/\U$1/;  # up-case, from "ok" to "OK"

                    my $color_state;
                    if ($type eq 'hosts') {
                        $color_state = colorize_hoststate($state);
                    }
                    elsif ($type eq 'services') {
                        $color_state = colorize_servicestate($state);
                    }
                    else {
                        $bot->log_warning("Invalid overview type \"".escape_nonprints($type)."\".");
                        return "Error parsing backend output! This seems to be neither hosts nor services overview...";
                    }

                    # Insert count into colorized state.
                    $color_state =~ s/^(\x03\d+,\d+)(.*)$/$1\x02\x02$count $2/;

                    # Append to output line accumulator.
                    $oline_accum .= " $color_state";
                }
            }
            $pass_back->($oline_accum) if length($oline_accum);
            $oline_accum = '';

            $bot->log_info("Done with processing command 'overview'.");
            #return undef;
            return "End of output of command 'overview'.";
        }
        elsif (/^overview hosts$/)
        {
            $bot->log_info("Request for command 'overview hosts'; starting icli...");

            my $result = `icli -v -C -xn -o -lh`;
            foreach my $line (split(/\n/, $result))
            {
                next unless (length($line) >= 1);

                # For now, simply pass on the icli output lines unmodified,
                # and with no output size limiting...
                $pass_back->($line);
            }

            $bot->log_info("Done with processing command 'overview hosts'.");
            #return undef;
            return "End of output of command 'overview hosts'.";
        }
        elsif (/^problems$/)
        {
            $bot->log_info("Request for command 'problems'; starting icli...");

            #my $result = `icli -C -xn -z'!o'`;
            my $result = `icli -v -C -xn -z'!o'`;
            foreach my $line (split(/\n/, $result))
            {
                next unless (length($line) >= 1);

                # For now, simply pass on the icli output lines unmodified,
                # and with no output size limiting...
                $pass_back->($line);
            }

            $bot->log_info("Done with processing command 'problems'.");
            #return undef;
            return "End of output of command 'problems'.";
        }
        elsif (/^problem hosts$/)
        {
            $bot->log_info("Request for command 'problem hosts'; starting icli...");

            my $result = `icli -v -C -xn -lh -z'!o'`;
            foreach my $line (split(/\n/, $result))
            {
                next unless (length($line) >= 1);

                # For now, simply pass on the icli output lines unmodified,
                # and with no output size limiting...
                $pass_back->($line);
            }

            $bot->log_info("Done with processing command 'problem hosts'.");
            #return undef;
            return "End of output of command 'problem hosts'.";
        }
        elsif (/^downtimes$/)
        {
            $bot->log_info("Request for command 'downtimes'; starting icli...");

            my $result = `icli -v -C -xn -ld`;
            foreach my $line (split(/\n/, $result))
            {
                next unless (length($line) >= 1);

                # For now, simply pass on the icli output lines unmodified,
                # and with no output size limiting...
                $pass_back->($line);
            }

            $bot->log_info("Done with processing command 'downtimes'.");
            #return undef;
            return "End of output of command 'downtimes'.";
        }
        elsif (/^host\s+(\S+)\s*$/)
        {
            $bot->log_info("Request for command 'host'");

            my $host = $1;
            unless ($host =~ /^[A-Za-z0-9.][-A-Za-z0-9.,]*$/)
            {
                $bot->log_info("Invalid host: \"".escape_nonprints($host)."\"");
                return "Invalid host.";
            }

            $bot->log_debug("Starting icli...");
            my $result = `icli -v -C -xn -lh -h '$host'`;
            foreach my $line (split(/\n/, $result))
            {
                next unless (length($line) >= 1);

                # For now, simply pass on the icli output lines unmodified,
                # and with no output size limiting...
                $pass_back->($line);
            }

            $bot->log_info("Done with processing command 'host'.");
            #return undef;
            return "End of output of command 'host'.";
        }
        elsif (/^services\s+on\s+(\S+)\s*$/)
        {
            $bot->log_info("Request for command 'services on'");

            my $host = $1;
            unless ($host =~ /^[A-Za-z0-9.][-A-Za-z0-9.,]*$/)
            {
                $bot->log_info("Invalid host: \"".escape_nonprints($host)."\"");
                return "Invalid host.";
            }

            $bot->log_debug("Starting icli...");
            my $result = `icli -v -C -xn -ls -h '$host'`;
            foreach my $line (split(/\n/, $result))
            {
                next unless (length($line) >= 1);

                # For now, simply pass on the icli output lines unmodified,
                # and with no output size limiting...
                $pass_back->($line);
            }

            $bot->log_info("Done with processing command 'services on'.");
            #return undef;
            return "End of output of command 'services on'.";
        }
        elsif (/^service\s+(\S.*?\S)(?:\s+on\s+(\S+))?\s*$/)
        {
            $bot->log_info("Request for command 'service'");

            my ($service, $host) = ($1, $2);
            unless (!defined($host) || $host =~ /^[A-Za-z0-9.][-A-Za-z0-9.,]*$/)
            {
                $bot->log_info("Invalid host: \"".escape_nonprints($host)."\"");
                return "Invalid host.";
            }
            unless ($service =~ m#^[A-Za-z0-9.][-A-Za-z0-9., /]*$#)
            {
                $bot->log_info("Invalid service: \"".escape_nonprints($service)."\"");
                return "Invalid service.";
            }

            $bot->log_debug("Starting icli...");
            my $result = defined($host)
                ? `icli -v -C -xn -ls -h '$host' -s '$service'`
                : `icli -v -C -xn -ls            -s '$service'`;
            foreach my $line (split(/\n/, $result))
            {
                next unless (length($line) >= 1);

                # For now, simply pass on the icli output lines unmodified,
                # and with no output size limiting...
                $pass_back->($line);
            }

            $bot->log_info("Done with processing command 'service'.");
            #return undef;
            return "End of output of command 'service'.";
        }
        else
        {
            $bot->log_info("Unknown command \"".escape_nonprints($_)."\".");
            return "Unknown command.";
        }
    }

    # Say nothing, if we should get here.
    $bot->log_notice("Saying nothing as fallback.");
    return undef;
}

sub help
{
    return "Available commands: problems, problem hosts, downtimes, host FOO,BAR,BAZ, services on FOO,BAR,BAZ, service MY SERVICE,ANOTHER SERVICE[ on HOST1,HOST2,HOST3]";
}

1;
