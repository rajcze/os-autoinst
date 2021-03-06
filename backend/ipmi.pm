# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2015 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package backend::ipmi;
use strict;
use base ('backend::baseclass');
use threads;
use threads::shared;
require File::Temp;
use File::Temp ();
use Time::HiRes qw(sleep gettimeofday);
use IO::Select;
use IO::Socket::UNIX qw( SOCK_STREAM );
use IO::Handle;
use Data::Dumper;
use POSIX qw/strftime :sys_wait_h/;
use JSON;
require Carp;
use Fcntl;
use bmwqemu qw(fileContent diag save_vars diag);
use testapi qw(get_required_var);
use IPC::Run ();
require IPC::System::Simple;
use autodie qw(:all);

sub new {
    my $class = shift;
    get_required_var('WORKER_HOSTNAME');
    return $class->SUPER::new;
}

use Time::HiRes qw(gettimeofday);

sub ipmi_cmdline {
    my ($self) = @_;

    return ('ipmitool', '-H', $bmwqemu::vars{IPMI_HOSTNAME}, '-U', $bmwqemu::vars{IPMI_USER}, '-P', $bmwqemu::vars{IPMI_PASSWORD});
}

sub ipmitool {
    my ($self, $cmd) = @_;

    my @cmd = $self->ipmi_cmdline();
    push(@cmd, split(/ /, $cmd));

    my ($stdin, $stdout, $stderr, $ret);
    $ret = IPC::Run::run(\@cmd, \$stdin, \$stdout, \$stderr);
    chomp $stdout;
    chomp $stderr;

    die join(' ', @cmd) . ": $stderr" unless ($ret);
    bmwqemu::diag("IPMI: $stdout");
    return $stdout;
}

sub restart_host {
    my ($self) = @_;

    $self->ipmitool("chassis power off");
    while (1) {
        my $stdout = $self->ipmitool('chassis power status');
        last if $stdout =~ m/is off/;
        $self->ipmitool('chassis power off');
        sleep(2);
    }

    $self->ipmitool("chassis power on");
    while (1) {
        my $ret = $self->ipmitool('chassis power status');
        last if $ret =~ m/is on/;
        $self->ipmitool('chassis power on');
        sleep(2);
    }
}

sub relogin_vnc {
    my ($self) = @_;

    if ($self->{vnc}) {
        close($self->{vnc}->socket);
        sleep(1);
    }

    my $vnc = $testapi::distri->add_console(
        'sut',
        'vnc-base',
        {
            hostname => $bmwqemu::vars{IPMI_HOSTNAME},
            port     => 5900,
            username => $bmwqemu::vars{IPMI_USER},
            password => $bmwqemu::vars{IPMI_PASSWORD},
            ikvm     => 1
        });
    $vnc->backend($self);
    $self->select_console({testapi_console => 'sut'});

    return 1;
}

sub do_start_vm() {
    my ($self) = @_;

    # remove backend.crashed
    $self->unlink_crash_file;
    $self->restart_host;
    $self->relogin_vnc;
    $self->start_serial_grab;
    return {};
}

sub do_stop_vm {
    my ($self) = @_;

    $self->ipmitool("chassis power off");
    $self->stop_serial_grab();
    return {};
}

sub status {
    my ($self) = @_;
    print "status ignored\n";
    return;
}

# serial grab

sub start_serial_grab {
    my ($self) = @_;

    $self->{serialpid} = fork();
    if ($self->{serialpid} == 0) {
        setpgrp 0, 0;
        open(my $serial, '>',  $self->{serialfile});
        open(STDOUT,     ">&", $serial);
        open(STDERR,     ">&", $serial);
        my @cmd = ('/usr/sbin/ipmiconsole', '-h', $bmwqemu::vars{IPMI_HOSTNAME}, '-u', $bmwqemu::vars{IPMI_USER}, '-p', $bmwqemu::vars{IPMI_PASSWORD});

        # zypper in dumponlyconsole, check devel:openQA for a patched freeipmi version that doesn't grab the terminal
        push(@cmd, '--dumponly');

        # our supermicro boards need workarounds to get SOL ;(
        push(@cmd, qw/-W nochecksumcheck/);

        exec(@cmd);
        die "exec failed $!";
    }
    return;
}

sub stop_serial_grab {
    my ($self) = @_;
    return unless $self->{serialpid};
    kill("-TERM", $self->{serialpid});
    return waitpid($self->{serialpid}, 0);
}

# serial grab end

1;

# vim: set sw=4 et:
