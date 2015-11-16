package xplhal::core::events;

use strict;

use String::Util 'trim';
use XML::Simple;
use xplhal::utils::misc;

my $eventdata;
my $isDirty;

sub init {
  load();
};

sub load {
  my $FD;
  if (open($FD,'./data/xplhal_events.xml')) {
    close($FD);
    $eventdata = XMLin('./data/xplhal_events.xml',forcearray=>1,keyattr => []);

    if (ref($eventdata->{event}) ne 'ARRAY'){
      xplhal::utils::misc::writeErrorLog "Warning: The events cache is corrupt and is being ignored.\n";
      $eventdata = {};
    }
  } else {
    $eventdata = {};
    print "Creating new events hash.\n";
  }
  $isDirty = 0;
};

sub save {
  if ($isDirty == 1 && defined($eventdata)) {
    my $eventsxml = XMLout($eventdata);
    my $FD;
    open($FD,'> ./data/xplhal_events.xml');
    print $FD $eventsxml;
    close($FD);
    $isDirty = 0;
  }
};

sub checkEvents {
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year += 1900;
  $mon += 1;

  # Check to see if any events need to be executed
  foreach my $event (@{$eventdata->{"event"}}) {
    if (!defined($event->{nextruntime}) || $event->{nextruntime} eq "") {
      determineNextRunTime($event);
    }

    my ($eventyear, $eventmon, $eventday, $eventhour, $eventmin, $eventsec) = parseDateTime($event->{nextruntime});
    if (!defined($eventyear) || !defined($eventmon) || !defined($eventday) || !defined($eventhour) || !defined($eventmin)) {
      xplhal::utils::misc::writeErrorLog "Ignoring event $event->{tag} because it has no valid next run time.";
    } else {
#print "Checking $year $eventyear $mon $eventmon $mday $eventday $hour $eventhour $min $eventmin\n\n";
      if ($year > $eventyear || ($year == $eventyear && (($mon == $eventmon && $mday >= $eventday) || $mon > $eventmon) && $hour >= $eventhour && $min >= $eventmin)) { #  && $sec >= $eventsec)) {
        xplhal::utils::misc::writeErrorLog("Executing $event->{tag} because it is after $event->{nextruntime}");
        execute($event->{tag});

        if (uc($event->{recurring}) eq 'TRUE') {
        determineNextRunTime($event);
    xplhal::utils::misc::writeErrorLog("$event->{starttime}, next run=$event->{nextruntime}");
        } else {
          deleteEvent($event->{tag});
        }
      }
    }
  }
};

sub parseDateTime {
  my ($year, $mon, $mday, $hour, $min, $sec);
  my $datetimestring = shift;

  if (defined($datetimestring) && index($datetimestring," ") > 0) {
    my $datestring = substr($datetimestring,0,index($datetimestring," "));
    $datestring =~ s/\//-/g;
    ($year, $mon, $mday) = split(/-/,$datestring);
    if ($mday > $year) {
      my $tempval = $year;
      $year = $mday;
      $mday = $tempval;
    }
    my $timestring = substr($datetimestring,length($datestring)+1,length($datetimestring)-length($datestring)-1);
    ($hour, $min, $sec) = split(/:/,$timestring);
    if (!defined($sec)) {
      $sec = 0;
    }
  }
  return ($year, $mon, $mday, $hour, $min, $sec);
};

sub execute {
  my $eventname = uc shift;
  my ($subname, $params);
  foreach my $event (@{$eventdata->{event}}) {
    if (uc($event->{tag}) eq $eventname) {
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
      if ($wday==7) {
        $wday = 0;
      }

      if (lc $event->{recurring} ne "true" || substr($event->{dow},$wday,1) eq 'Y' || substr($event->{dow},$wday,1) eq '1') {
        if (lc($event->{runsub}) eq '{determinator}') {
          xplhal::core::determinator::executeByName($event->{param});
        } else {
          xplhal::core::scripting::run($event->{runsub});
        }
      }
    }
  }
};

sub xhcpListEvents {
  my $clientsock = shift;
  print $clientsock "218 OK\r\n";
  foreach my $event (@{$eventdata->{event}}) {
    if (uc $event->{recurring} eq 'TRUE') {
      print $clientsock "$event->{tag}\t$event->{runsub}\t$event->{param}\t$event->{starttime}\t$event->{endtime}\t$event->{dow}\t$event->{nextruntime}\t\r\n";
    }
  }
  print $clientsock ".\r\n";
};

sub xhcpListSingleEvents {
  my $clientsock = shift;
  print $clientsock "218 OK\r\n";
  foreach my $event (@{$eventdata->{event}}) {
    if (uc $event->{recurring} ne 'TRUE') {
      print $clientsock "$event->{tag}\t$event->{runsub}\t$event->{param}\t$event->{nextruntime}\t\r\n";
    }
  }
  print $clientsock ".\r\n";
};


sub xhcpAddEvent {
  my $clientsock = shift;
  print $clientsock "319 Continue\r\n";
  my ($tag,$dow,$endtime,$interval,$params,$rand,$starttime,$subname, $date);

  # Set some sensible defaults to allow XHCP clients to submit only partial data
  $dow = "1111111";
  $interval = "0";
  $rand = "0";

  my $line = <$clientsock>;
  my ($lhs, $rhs);
  while (defined($line)) {
    if ($line eq ".\r\n") {
      $line = undef;
    } else {
      $line =~ s/\r\n//g;
      if (index($line,'=') > 0) {
        $lhs = uc substr($line,0,index($line,'='));
        $rhs = substr($line,index($line,'=')+1,length($line)-length($lhs)-1);
        if ($lhs eq 'DOW') {
          $dow = trim $rhs;
        } elsif ($lhs eq 'ENDTIME') {
          $endtime = $rhs;
        } elsif ($lhs eq 'INTERVAL') {
          $interval = $rhs;
        } elsif ($lhs eq 'PARAMS') {
          $params = $rhs;
        } elsif ($lhs eq 'RAND') {
          $rand = $rhs;
        } elsif ($lhs eq 'STARTTIME') {
          $starttime = $rhs;
        } elsif ($lhs eq 'DATE') {
          $date = $rhs;
        } elsif ($lhs eq 'SUBNAME') {
          $subname = trim $rhs;
        } elsif ($lhs eq 'TAG') {
          $tag = $rhs;
        }
      }
      $line = <$clientsock>;
    }
  }

  # Make sure we have mandatory fields
  if (!defined($tag)) {
    print $clientsock "500 Event name missing\r\n";
  } elsif (!defined($starttime) && !defined($date)) {
    print $clientsock "500 Start time or date missing\r\n";
  } elsif (!defined($endtime) && !defined($date)) {
    print $clientsock "500 End time or date missing\r\n";
  } else {
    $date = fixMonths($date);
    my $event = {
      dow => $dow,
      endtime => $endtime,
      interval => $interval,
      nextruntime => (defined($date)) ? $date : undef,
      param => $params,
      randomtime => $rand,
      runsub => $subname,
      starttime => (defined($starttime)) ? $starttime : $date,
      tag => $tag,
      recurring => (defined($starttime)) ? 'True' : 'false'
    };
print "*** New event ***\n$event->{starttime}, $event->{tag}\n\n";

    deleteEvent($event->{tag});
    push @{$eventdata->{event}}, $event;  
    $isDirty = 1;
    print $clientsock "219 OK\r\n";
  }
};

sub addSingleEvent {
  my $tag = shift;
  my $params = shift;
  my $starttime = shift;
  my $subname = shift;

  $starttime = fixMonths($starttime);

  # Make sure we have the needed parameters in order to create the event
  if (!defined($tag) || !defined($starttime) || !defined($subname)) {
    print "Cannot create event as some data is missing.\n";
    return;
  }

    my $event = {
      dow => "",
      endtime => "",
      interval => 0,
      param => $params,
      randomtime => 0,
      runsub => $subname,
      starttime => $starttime,
      tag => $tag,
      nextruntime => $starttime,
      recurring => 'False'
    };

  deleteEvent($tag);
    push @{$eventdata->{event}}, $event;  
    $isDirty = 1;
};

sub xhcpAddSingleEvent {
  my $clientsock = shift;
  print $clientsock "319 Continue\r\n";
  my ($tag,$params,$starttime,$subname);

  my $line = <$clientsock>;
  my ($lhs, $rhs);
  while (defined($line)) {
    if ($line eq ".\r\n") {
      $line = undef;
    } else {
      $line =~ s/\r\n//g;
      if (index($line,'=') > 0) {
        $lhs = uc substr($line,0,index($line,'='));
        $rhs = substr($line,index($line,'=')+1,length($line)-length($lhs)-1);
        if ($lhs eq 'PARAMS') {
          $params = $rhs;
        }
        if ($lhs eq 'DATE') {
          $starttime = $rhs;
        }
        if ($lhs eq 'SUBNAME') {
          $subname = $rhs;
        }
        if ($lhs eq 'TAG') {
          $tag = $rhs;
        }
      }
      $line = <$clientsock>;
    }
  }

  # Make sure we have mandatory fields
  if (!defined($tag)) {
    print $clientsock "500 Event name missing\r\n";
  } elsif (!defined($starttime)) {
    print $clientsock "500 Start time missing\r\n";
  } else {
    addSingleEvent($tag, $params, $starttime, $subname);
    print $clientsock "219 OK\r\n";
  }
};

sub xhcpDelEvent {
  my $clientsock = shift;
  my $eventname = shift;
  if (deleteEvent($eventname)) {
    print $clientsock "223 OK\r\n";
  }
  else {
    print $clientsock "422 No such event\r\n";
  }
};

sub eventExists {
  my $eventname = uc shift;
  my $found = 0;
  foreach my $event (@{$eventdata->{event}}) {
    if (uc($event->{tag}) eq $eventname) {
      $found = 1;
    }
  }

  return $found;
};

sub deleteEvent {
  my $eventname = uc shift;
  my $newevents;
  my $found = 0;
  foreach my $event (@{$eventdata->{event}}) {
    if (uc($event->{tag}) ne $eventname) {
    push @{$newevents->{event}}, $event;  
    }
    else {
      $found = 1;
    }
  }
  if ($found==1) {
    $eventdata = $newevents;
    $isDirty = 1;
  }
  return $found;
};

sub fixMonths {
  my $date = shift;

  if (!defined($date)) {
    return undef;
  }

  $date =~ s/jan/01/gi;
  $date =~ s/feb/02/gi;
  $date =~ s/mar/03/gi;
  $date =~ s/apr/04/gi;
  $date =~ s/may/05/gi;
  $date =~ s/jun/06/gi;
  $date =~ s/jul/07/gi;
  $date =~ s/aug/08/gi;
  $date =~ s/sep/09/gi;
  $date =~ s/oct/10/gi;
  $date =~ s/nov/11/gi;
  $date =~ s/dec/12/gi;
  return $date;
};

sub determineNextRunTime {
  my $event = shift;

  if (uc($event->{recurring}) ne 'TRUE') {
    if (!defined($event->{starttime})) {
      print "Event has no start time.\n";
    } else {
      $event->{nextruntime} = $event->{starttime};
      print "Set next run time for $event->{tag} to $event->{nextruntime}\n";
      }
    return;
  }

  my ($lastyear, $lastmon, $lastday, $lasthour, $lastmin) = parseDateTime($event->{lastruntime});
      my ($starthour, $startminute) = split(/:/,$event->{starttime});
      my ($endhour, $endminute) = split(/:/,$event->{endtime});
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year += 1900;
  $mon += 1;

  # Fill in any missing or invalid elements of the event
  if (!defined($event->{interval}) || $event->{interval} eq "") { $event->{interval} = 0; }
  if (!defined($lastyear)) { $lastyear = $year; }
  if (!defined($lastmon)) { $lastmon = $mon; }
  if (!defined($lastday)) { $lastday = $mday; }
  if (!defined($lasthour)) { $lasthour = $starthour; }
  if (!defined($lastmin)) { $lastmin = $startminute; }

  # First handle events with no interval
  if ($event->{interval}==0) {
    if ($hour > $starthour || $hour==$starthour && $min >= $startminute) {
      $mday += 1;
    }
    $event->{nextruntime} = "$year-$mon-$mday $event->{starttime}";
  } else {
    # Handle intervals
    $lasthour = $hour;
    $lastmin = $min + $event->{interval};

    while ($lastmin > 59) {
      $lasthour++;
      $lastmin -= 60;
    }
    if ($lasthour > 23) {
      $lastday += 1;
      $lasthour -= 24;
    }
    $event->{nextruntime} = "$lastyear-$lastmon-$lastday $lasthour:$lastmin";
  }

    $isDirty = 1;
};

sub xhcpGetEvent {
  my $clientsock = shift;
  my $eventname = uc shift;
  my $found = 0;
  foreach my $event (@{$eventdata->{event}}) {
    if (uc($event->{tag}) eq $eventname) {
      print $clientsock "222 OK\r\n";
      print $clientsock "tag=$event->{tag}\r\n";
      $event->{dow} =~ s/N/0/gi;
      $event->{dow} =~ s/Y/1/gi;
      print $clientsock "dow=$event->{dow}\r\n";
      print $clientsock "endtime=$event->{endtime}\r\n";
      print $clientsock "interval=$event->{interval}\r\n";
      print $clientsock "nextruntime=$event->{nextruntime}\r\n";
      print $clientsock "params=$event->{param}\r\n";
      print $clientsock "rand=$event->{randomtime}\r\n";
      print $clientsock "subname=$event->{runsub}\r\n";
      print $clientsock "starttime=$event->{starttime}\r\n";
      print $clientsock "recurring=$event->{recurring}\r\n";
      print $clientsock ".\r\n";
      $found = 1;
    }
  }

  if ($found==0) {
    print $clientsock "422 Event $eventname not found\r\n";
  }
};

1;
