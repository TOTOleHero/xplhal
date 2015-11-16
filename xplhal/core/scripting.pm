package xplhal::core::scripting;

use strict;
use warnings;

use xplhal::utils::email;

sub init {
  mkdir "./data/scripts";
  run("xplhal_load.xpl");
};


sub xhcpDelScript {
  my $clientsock = shift;
  my $filename = lc shift;
  my $path = "./data/scripts/$filename";
  unlink $path;
  print $clientsock "214 OK\r\n";
}

sub xhcpListScripts {
  my $clientsock = shift;
  my $directory = shift;
  my $path = (defined($directory)) ? "./data/scripts/$directory" : "./data/scripts";
  print $clientsock "212 OK\r\n";
  opendir(DIR, $path) || die "can't opendir determinator: $!";
  my $file = readdir(DIR);
  while (defined($file)) {
    if ($file =~ /^\.\.?$/) {
    }
    else {
    print $clientsock "$file\r\n";
    }
    $file = readdir(DIR);
  }
  closedir DIR;
  print $clientsock ".\r\n";
};

sub xhcpListSubs {
  my $clientsock = shift;
  my $directory = shift;
  my $path = (defined($directory)) ? "./data/scripts/$directory" : "./data/scripts";
  print $clientsock "224 OK\r\n";
  opendir(DIR, $path) || die "can't opendir determinator: $!";
  my $file = readdir(DIR);
  while (defined($file)) {
    if ($file =~ /^\.\.?$/) {
    }
    else {
$file = substr($file,0,index($file,'.'));
    print $clientsock "$file\r\n";
    }
    $file = readdir(DIR);
  }
  closedir DIR;
  print $clientsock ".\r\n";
}

sub xhcpPutScript {
  my $clientsock = shift;
  my $filename = lc shift;
  my $scripttext = '';
  print $clientsock "311 Enter script\r\n";
  my $line = <$clientsock>;
  while (defined($line)) {
    if ($line eq ".\r\n") {
      $line = undef;
    } else {
      $scripttext .= $line;
      $line = <$clientsock>;
    }
  }

  open(FD,"> ./data/scripts/$filename");
  print FD $scripttext;
  close(FD);
  print $clientsock "211 OK\r\n";
};

sub xhcpGetScript {
  my $clientsock = shift;
  my $scriptname = shift;
  my $filename = "./data/scripts/$scriptname";
  my $fd;

  if (open($fd,$filename)) {
    binmode($fd); 
    print $clientsock "210 OK\r\n";
    my $file = do { local $/; <$fd> };
    print $clientsock $file; 
    close($fd);
    print $clientsock ".\r\n";
  } else {
  print $clientsock "410 No such script\r\n";
  }
};

sub xhcpRunSub {
  my $clientsock = shift;
  my $script = shift;
  my $param = shift;
  if (run($script, $param)==1) {
    print $clientsock "203 OK\r\n";
  } else {
    print $clientsock "403 Script not found\r\n";
  }
};

sub runAsync {
  my $script = $_[0];
  my $file = $_[1];
  my $param = $_[2];

  eval($file);

  if (defined($@) && $@ ne "") {
    xplhal::utils::misc::writeErrorLog("$script $@");
  }
}

sub run {
  my $script = lc shift;
  my $param = shift;
  my $fd;

  # Add the .xpl filename suffix if it is not supplied
  if (!($script =~ /\.xpl$/)) {
    $script .= '.xpl';
  }

  if (open($fd,"./data/scripts/$script")) {
    binmode($fd); 
    my $file = do { local $/; <$fd> };
    close($fd);
    runAsync $script, $file, $param;
  return 1;
  }

  return 0;
};

sub processMessage {
  my $msg = shift;
  my $msg_source = shift;
  my $msg_schema = shift;
  my ($msg_source_vendor, $msg_source_device, $msg_source_instance) = $msg_source =~ /^(\w+)-(\w+)\.(\w+)$/x;

  # Run the script for the device
  run("$msg_source_vendor\_$msg_source_device\_$msg_source_instance.xpl",$msg);
};

# Wrappers
sub xplhal_eventExists {
  return xplhal::core::events::eventExists($_[0]);
};

sub xplhal_getGlobal {
  return xplhal::core::globals::get($_[0]);
};

sub xplhal_sendEmail {
  xplhal::utils::email::send($_[0], $_[1], $_[2], $_[3]);
}

sub xplhal_sendXplMsg {
  xplhal::core::xpl::sendxplmsg($_[0], $_[1], $_[2], $_[3]);
}

sub xplhal_setGlobal {
  return xplhal::core::globals::set($_[0],$_[1]);
};

sub currentHour {
  return xplhal::utils::misc::currentHour();
};

sub currentMinute {
  return xplhal::utils::misc::currentMinute();
};

sub xplhal_writeErrorLog {
  xplhal::utils::misc::writeErrorLog($_[0]);
};

1;