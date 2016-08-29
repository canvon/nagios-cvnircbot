
# nagios-cvnircbot -- canvon IRC bot for monitoring Nagios monitoring

> Send Nagios log messages to IRC, and let Nagios status be queried actively
> from IRC

This is an IRC (Internet Relay Chat) bot that parses the Nagios log file on the
central IT infrastructure monitoring host and passes "interesting" things on
to IRC. At the moment, that means it will send host/service alerts as notices,
and notifications as normal messages addressed to the Nagios CONTACTNAME
(which presumably is the same as a nick on IRC, otherwise just set a highlight
in your IRC client).

The bot also can be talked to, which gives direct access to the Nagios status
file, currently via Icinga `icli` invocations (which is compatible to Nagios).
Addressing the bot and saying "problems" to it will dump the current state of
services with problems, either to the channel or query where it was addressed.
There are further commands, address the bot saying "help" to get a short
overview.


## ToC

This README contains: (**Table of Contents**)

  * [Setup instructions](#setup)

    * [Basic setup instructions](#basic-setup)

    * [Bot commands and how to make them work](#bot-commands)

    * [Log rotation and how to work-around it](#log-rotation)

  * [Contact information](#contact)


## Setup

### Basic setup

You can run the bot right from the git repository, as `./cvnircbot.pl`; but you
have to copy the `example-cvnircbotrc` to `~/.cvnircbot/cvnircbotrc` first, and
edit the file to set the IRC server to use, bot nickname, channel and other
things.

### Bot commands

To make the active queries from IRC work, you'll also have to set up an `icli`
that can be invoked by the bot to get data. In my case, this is a wrapper script
in `~/bin/icli` (it has to be on your $PATH) which uses `sudo` to aquire read
permissions on the Nagios status file. Often the group the web server runs in
will have such read permission. So I use (on _Debian 8_):

```
#!/bin/bash
exec sudo -g www-data icli --config /etc/nagios3/nagios.cfg --status-file /var/cache/nagios3/status.dat "$@"
```

Save the two-liner to `~/bin/icli` and `chmod +x ~/bin/icli`. Giving
password-less sudo permissions for group `www-data` (or what the webserver
your Nagios web-frontend is running on uses) to the user the bot runs as
is left as an exercise to the reader.

### Log rotation

The bot currently does not cope with Nagios' automatic log rotation.

As a work-around, I recommend running the bot in a loop, like this:

```
nagios-cvnircbot$ while true ; do ./cvnircbot.pl ; sleep 600 ; done  # restart every 10 minutes
```

Then make it exit regularly from `cron`. In a per-user `crontab`,
using `crontab -e` to edit and `crontab -l` to list:

```
# m h  dom mon dow   command
2 0  1 * *   pkill cvnircbot.pl
```

This would make the bot exit on the 1st of each month, two minutes
past mid-night. (This is just after my Nagios instance rotates its logs.)
It will come back automatically after the timeout you set on the
command line above expires.


## Thanks

Thanks go to ArneB <http://www.arneb.de/>, for explaining
how _non-blocking I/O_ might be used to poll a log file
from a Perl IRC bot.


## Contact

The **nagios-cvnircbot**, canvon IRC bot for monitoring Nagios monitoring, has
been written by:

  * Fabian Pietsch <fabian-cvnircbot@canvon.de>  (primary author from 2015-2016)

The project is currently (as of 2016-08-29) hosted on GitHub:

  * https://github.com/canvon/nagios-cvnircbot

