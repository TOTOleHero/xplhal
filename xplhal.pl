#!/usr/bin/perl -w

# xPLHal for Perl
#
# Version 0.1
#
# Copyright (C) 2003-2015 John Bent
# http://xpl.microlitesoftware.co.uk/xplhal
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

use strict;
use warnings;
use feature qw/say/;

use xplhal::control::xhcp;
use xplhal::core::determinator;
use xplhal::core::events;
use xplhal::core::globals;
use xplhal::core::hub;
use xplhal::core::scripting;
use xplhal::core::prefs;
use xplhal::core::x10;
use xplhal::core::xpl;

# Variable to store the time we last checked for things
# such as timed events. This should be no more frequent than 
# every eight seconds.
my $lastLoop = 0;

sub Banner {
  print "xPLHal for Perl ($xplhal::core::prefs::longos)\nCopyright (C) 2003-2015 by John Bent\n";
};

sub main {
  xplhal::core::prefs::init();
  Banner();
  xplhal::core::hub::init();
  xplhal::core::config::init();
  xplhal::core::xpl::init();
  xplhal::core::globals::init();
  xplhal::core::scripting::init();
  xplhal::core::x10::init();
  xplhal::core::determinator::init();
  xplhal::core::events::init();
  xplhal::control::xhcp::init();

  xplhal::core::globals::set('LOADED',xplhal::utils::misc::currentTime);

  while (!idle()) {}

  xplhal::core::globals::set('UNLOADED',Time::HiRes::time());

};

sub idle {
  my $select_time = 10;

  if (time > $lastLoop+8) {
    # Send a heartbeat if we need to
    xplhal::core::xpl::sendHeartbeat();

    # Execute any timed events that need to run
    xplhal::core::events::checkEvents();

    # Save any data that has changed
    saveData();

    $lastLoop = time;
  }

  # Wait in select for incoming data
  xplhal::utils::select::select($select_time);

  return 0;
};

sub saveData {
  # Save the globals if any have changed
  xplhal::core::globals::save();

  # Save events if any have changed
  xplhal::core::events::save();
};

$SIG{INT} = sub {
  saveData();
  die "Terminated gracefully by signal.";
};

main();


1;
