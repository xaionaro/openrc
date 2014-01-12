#! /usr/bin/perl
#
# update-rc.d to support OpenRC.
# modified from update-rc.d of Debian by Bill Wang <freecnpro@gmail.com>

use strict;
use warnings;

# Print usage message and die.

sub usage {
	print STDERR "update-rc.d: error: @_\n" if ($#_ >= 0);
	print STDERR <<EOF;
usage: update-rc.d [-n] [-f] <basename> remove
       update-rc.d [-n] <basename> defaults [NN | SS KK]
       update-rc.d [-n] <basename> start|stop NN runlvl [runlvl] [...] .
       update-rc.d [-n] <basename> disable|enable [S|2|3|4|5]
		-n: not really
		-f: force

The disable|enable API is not stable and might change in the future.
EOF
	exit (1);
}

exit openrc_updatercd(@ARGV);

sub info {
    print STDOUT "update-rc.d: @_\n";
}

sub warning {
    print STDERR "update-rc.d: warning: @_\n";
}

sub error {
    print STDERR "update-rc.d: error: @_\n";
    exit (1);
}

sub error_code {
    my $rc = shift;
    print STDERR "update-rc.d: error: @_\n";
    exit ($rc);
}

## Dependency based
sub openrc_updatercd {
    my @args = @_;
    my @opts;
    my $scriptname;
    my $action;
    my $notreally = 0;
    my @orig_argv = @args;

    while($#args >= 0 && ($_ = $args[0]) =~ /^-/) {
        shift @args;
        if (/^-n$/) { push(@opts, $_); $notreally++; next }
        if (/^-f$/) { push(@opts, $_); next }
        if (/^-h|--help$/) { &usage; }
        usage("unknown option");
    }

    usage("not enough arguments") if ($#args < 1);

    $scriptname = shift @args;
    $action = shift @args;
    if ("remove" eq $action) {
	    # let rc-update handle the dangling symlinks
	    my $rc = system("rc-update", "-qqa", "delete", $scriptname);
	    exit 0;
    } elsif ("defaults" eq $action || "start" eq $action ||
             "stop" eq $action) {
        # All start/stop/defaults arguments are discarded so emit a
        # message if arguments have been given and are in conflict
        # with Default-Start/Default-Stop values of LSB comment.
        my $rln = cmp_args_with_defaults($scriptname, $action, @args);
	exit 0 if (!$rln);
        if ( -f "/etc/init.d/$scriptname") {
	    if("stop" ne $action){
		my $rc = system("rc-update", "add", $scriptname, rlconv($rln)) >> 8;
            	error_code($rc, "rc-update rejected the script header") if $rc;
            	exit $rc;
	    }
        } else {
            error("initscript does not exist: /etc/init.d/$scriptname");
        }
    } elsif ("disable" eq $action || "enable" eq $action) {
		my @rl = rlconv(join(' ', @args));
		if("disable" eq $action){
			my $rc = system("rc-update", "delete", $scriptname, @rl) >> 8;
			error_code($rc, "rc-update rejected the script header") if $rc;
        	exit $rc;
		}else{
			my $rc = system("rc-update", "add", $scriptname, @rl) >> 8;
			error_code($rc, "rc-update rejected the script header") if $rc;
        	exit $rc;
		}
    } else {
        usage();
    }
}

sub parse_def_start_stop {
    my $script = shift;
    my (%lsb, @def_start_lvls, @def_stop_lvls);

    open my $fh, '<', $script or error("unable to read $script");
    while (<$fh>) {
        chomp;
        if (m/^### BEGIN INIT INFO$/) {
            $lsb{'begin'}++;
        }
        elsif (m/^### END INIT INFO$/) {
            $lsb{'end'}++;
            last;
        }
        elsif ($lsb{'begin'} and not $lsb{'end'}) {
            if (m/^# Default-Start:\s*(\S?.*)$/) {
                @def_start_lvls = split(' ', $1);
            }
            if (m/^# Default-Stop:\s*(\S?.*)$/) {
                @def_stop_lvls = split(' ', $1);
            }
        }
    }
    close($fh);

    return (\@def_start_lvls, \@def_stop_lvls);
}

sub cmp_args_with_defaults {
    my ($name, $act) = (shift, shift);
    my ($lsb_start_ref, $lsb_stop_ref, $arg_str, $lsb_str);
    my (@arg_start_lvls, @arg_stop_lvls, @lsb_start_lvls, @lsb_stop_lvls);
    my $default_msg = ($act eq 'defaults') ? 'default' : '';

    ($lsb_start_ref, $lsb_stop_ref) = parse_def_start_stop("/etc/init.d/$name");
    @lsb_start_lvls = @$lsb_start_ref;
    @lsb_stop_lvls  = @$lsb_stop_ref;
    return if (!@lsb_start_lvls and !@lsb_stop_lvls);

    if ($act eq 'defaults') {
        @arg_start_lvls = (2, 3, 4, 5);
        @arg_stop_lvls  = (0, 1, 6);
    } elsif ($act eq 'start' or $act eq 'stop') {
        my $start = $act eq 'start' ? 1 : 0;
        my $stop = $act eq 'stop' ? 1 : 0;

        # The legacy part of this program passes arguments starting with
        # "start|stop NN x y z ." but the insserv part gives argument list
        # starting with sequence number (ie. strips off leading "start|stop")
        # Start processing arguments immediately after the first seq number.
        my $argi = $_[0] eq $act ? 2 : 1;

        while (defined $_[$argi]) {
            my $arg = $_[$argi];

            # Runlevels 0 and 6 are always stop runlevels
            if ($arg eq 0 or $arg eq 6) {
		$start = 0; $stop = 1;
            } elsif ($arg eq 'start') {
                $start = 1; $stop = 0; $argi++; next;
            } elsif ($arg eq 'stop') {
                $start = 0; $stop = 1; $argi++; next;
            } elsif ($arg eq '.') {
                next;
            }
            push(@arg_start_lvls, $arg) if $start;
            push(@arg_stop_lvls, $arg) if $stop;
        } continue {
            $argi++;
        }
    }

    if ($#arg_start_lvls != $#lsb_start_lvls or
        join("\0", sort @arg_start_lvls) ne join("\0", sort @lsb_start_lvls)) {
        $arg_str = @arg_start_lvls ? "@arg_start_lvls" : "none";
        $lsb_str = @lsb_start_lvls ? "@lsb_start_lvls" : "none";
        warning "$default_msg start runlevel arguments ($arg_str) do not match",
                "$name Default-Start values ($lsb_str)";
    }
    if ($#arg_stop_lvls != $#lsb_stop_lvls or
        join("\0", sort @arg_stop_lvls) ne join("\0", sort @lsb_stop_lvls)) {
        $arg_str = @arg_stop_lvls ? "@arg_stop_lvls" : "none";
        $lsb_str = @lsb_stop_lvls ? "@lsb_stop_lvls" : "none";
        warning "$default_msg stop runlevel arguments ($arg_str) do not match",
                "$name Default-Stop values ($lsb_str)";
    }

    return join(" ", @lsb_start_lvls);
}

sub rlconv {
	my @nrl;
	my $is_default = 0;
	my $runlevels = shift;
	for my $rl (split(' ', $runlevels)){
		if($rl =~ /^[Ss]$/){
			$rl = "sysinit";
		}elsif("1" eq $rl){
			$rl = "single";
		}elsif("0" eq $rl or "6" eq $rl){
			$rl = "shutdown";
		}else{
			$is_default++;
			if($is_default == 1){
				push(@nrl, "default");
				next;
			}else{
				next;
			}
		}
		push(@nrl, $rl);
	}

	return @nrl;
}
