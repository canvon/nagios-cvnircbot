
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


## Setup

You can run the bot right from the git repository, as `./cvnircbot.pl`; but you
have to copy the `example-cvnircbotrc` to `~/.cvnircbot/cvnircbotrc` first, and
edit the file to set the IRC server to use, bot nickname, channel and other
things.

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


## Contact

The _nagios-cvnircbot_, canvon IRC bot for monitoring Nagios monitoring, has
been written by:

  Fabian Pietsch <fabian-cvnircbot@canvon.de>  (primary author from 2015-2016)

The project is currently (as of 2016-08-29) hosted on GitHub:

  https://github.com/canvon/nagios-cvnircbot

