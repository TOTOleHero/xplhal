package xplhal::control::xhcp;

use strict;
use warnings;

use FindBin qw($Bin);
use IO::Socket;
use File::Spec::Functions qw(:ALL);

use xplhal::core::globals;
use xplhal::core::prefs;
use xplhal::utils::constants;
use xplhal::utils::misc;
use xplhal::utils::select;

my $xhcp_socket;

sub init {
  $xhcp_socket = IO::Socket::INET->new( Proto     => 'tcp',
									 LocalPort => 3865,
									 Listen    => SOMAXCONN,
									 ReuseAddr     => 1,
									 Reuse     => 1,
									 Timeout   => 0.001
  );
  die "can't setup the listening port 3865 for the XHCP server: $!" unless $xhcp_socket;
  defined(xplhal::utils::misc::blocking($xhcp_socket,0)) || die "Cannot set port nonblocking";
  xplhal::utils::select::addRead($xhcp_socket, \&acceptXhcp);
};

sub acceptXhcp {
  my $xhcpclientsock = $xhcp_socket->accept();
  if ($xhcpclientsock) {
    my $instancename = $xplhal::core::xpl::xpl_source;
    print $xhcpclientsock "200 $instancename Version 1.0 XHCP 1.5 ready\r\n";
    xplhal::utils::select::addRead($xhcpclientsock, \&processRequest);
  }
};

sub processRequest {
  my $clientsock = shift;
  my $firstline;

  if ($clientsock) {
    $clientsock->autoflush(1);
    $firstline = <$clientsock>;
    if (!defined($firstline)) { 
      closer($clientsock);
    } else { 
      chomp $firstline; 
      executeCmd($clientsock, $firstline);
    }
  }
};

sub executeCmd {
  my($clientsock, $command) = @_;
  $command = substr($command,0,length($command)-1);
  my @bits = split / /,$command;
    my $params;
  if (length($command) > length($bits[0])) {
    $params = substr($command,length($bits[0])+1,length($command)-length($bits[0])-1);
  }

  $bits[0] = uc($bits[0]);

  if ($bits[0] eq 'QUIT') {
    print $clientsock "221 OK\r\n";
  xplhal::utils::select::addRead($clientsock);
    closer($clientsock);
  } 
  elsif ($bits[0] eq 'ADDEVENT') {
    xplhal::core::events::xhcpAddEvent($clientsock);
  } elsif ($bits[0] eq 'ADDSINGLEEVENT') {
    xplhal::core::events::xhcpAddSingleEvent($clientsock);
  } elsif ($bits[0] eq 'CAPABILITIES') {
    xhcpCapabilities($clientsock);
  } elsif ($bits[0] eq 'DEBUG') {
    xhcpDebug($clientsock);
  } elsif ($bits[0] eq 'CLEARERRLOG') {
    xhcpClearErrLog($clientsock);
  } elsif ($bits[0] eq 'DELEVENT') {
    xplhal::core::events::xhcpDelEvent($clientsock,$params);
  } elsif ($bits[0] eq 'DELGLOBAL') {
    xplhal::core::globals::xhcpDelGlobal($clientsock, $params);
  } elsif ($bits[0] eq 'DELRULE') {
    xplhal::core::determinator::xhcpDelRule($clientsock, $params);
  } elsif ($bits[0] eq 'DELSCRIPT') {
    xplhal::core::scripting::xhcpDelScript($clientsock, $params);
  } elsif ($bits[0] eq 'GETERRLOG') {
    xhcpGetErrLog($clientsock);
  } elsif ($bits[0] eq 'GETEVENT') {
    xplhal::core::events::xhcpGetEvent($clientsock,$params);
  } elsif ($bits[0] eq 'GETGLOBAL') {
    xplhal::core::globals::xhcpGetGlobal($clientsock, $params);
  } elsif ($bits[0] eq 'GETCONFIGXML') {
    xhcpGetConfigXML($clientsock);
  } elsif ($bits[0] eq 'GETSCRIPT') {
    xplhal::core::scripting::xhcpGetScript($clientsock,$params);
  } elsif ($bits[0] eq 'GETRULE') {
    xplhal::core::determinator::xhcpGetRule($clientsock,$params);
  }
  elsif ($bits[0] eq 'GETSOURCE') {
    xhcpGetSource($clientsock);
  }
  elsif ($bits[0] eq 'LISTDEVICES') {
    xplhal::core::config::xhcpListDevices($clientsock);
  } elsif ($bits[0] eq 'LISTEVENTS') {
    xplhal::core::events::xhcpListEvents($clientsock);
  } elsif ($bits[0] eq 'LISTGLOBALS') {
    xplhal::core::globals::xhcpListGlobals($clientsock);
  } elsif ($bits[0] eq 'LISTRULES') {
    xplhal::core::determinator::xhcpListRules($clientsock);
  } elsif ($bits[0] eq 'LISTSCRIPTS') {
    xplhal::core::scripting::xhcpListScripts($clientsock);
  } elsif ($bits[0] eq 'LISTSINGLEEVENTS') {
    xplhal::core::events::xhcpListSingleEvents($clientsock);
  } elsif ($bits[0] eq 'LISTSUBS') {
    xplhal::core::scripting::xhcpListSubs($clientsock);
  } elsif ($bits[0] eq 'PUTCONFIGXML') {
    xhcpPutConfigXML($clientsock);
  } elsif ($bits[0] eq 'PUTSCRIPT') {
    xplhal::core::scripting::xhcpPutScript($clientsock,$params);
  } elsif ($bits[0] eq 'RUNRULE') {
    xplhal::core::determinator::xhcpRunRule($clientsock,$params);
  } elsif ($bits[0] eq 'RUNSUB') {
    xplhal::core::scripting::xhcpRunSub($clientsock,$bits[1],$bits[2]);
  } elsif ($bits[0] eq 'SENDXPLMSG') {
    xplhal::core::xpl::xhcpSendXplMsg($clientsock);
  }
  elsif ($bits[0] eq 'SETGLOBAL') {
    xplhal::core::globals::xhcpSetGlobal($clientsock,substr($command,10,length($command)-10));
  }
  elsif ($bits[0] eq 'SETRULE') {
    xplhal::core::determinator::xhcpSetRule($clientsock,$params);
  }
  else {
    print $clientsock "500 Command not recognised ($bits[0])\r\n";
  }
}

sub closer {
  my $clientsock = shift;

#  xplhal::utils::select::addWrite($clientsock, undef);
  xplhal::utils::select::addRead($clientsock, undef);	
  close $clientsock;
}

sub xhcpDebug {
  my $clientsock = shift;
  if (%xplhal::core::hub::hubs) {
    print $clientsock "HubClients=%xplhal::core::hub::hubs\r\n";
  } else {
    print $clientsock "HubClients=None\r\n";
  }
  my $readsockets = keys %xplhal::utils::select::readSockets;
  print $clientsock "ReadSockets=$readsockets\r\n";
  print $clientsock ".\r\n";
}

sub xhcpCapabilities {
  my $clientsock = shift;

  print $clientsock "236 10E11$xplhal::core::prefs::shortos\r\n";
}

sub xhcpGetSource {
  my $clientsock = shift;
  print $clientsock "202 $xplhal::core::xpl::xpl_source\r\n";
};

sub xhcpGetConfigXML {
  my $clientsock = shift;
  print $clientsock "209 OK\r\n";
  if (open(FD,'./data/xplhal.xml')) {
    my $line = <FD>;
    while (defined($line)) {
      print $clientsock $line;
      $line = <FD>;
    }
  }
  print $clientsock ".\r\n";
};

sub xhcpPutConfigXML {
  my $clientsock = shift;
  print $clientsock "315 Continue\r\n";
  open(FD,'> ./data/xplhal.xml');
  my $line = <$clientsock>;
  while (defined($line)) {
    if ($line eq ".\r\n") {
      $line = undef;
    }
    else {
      print FD $line;
      $line = <$clientsock>;
    }
  }
  close(FD);
  print $clientsock "215 OK\r\n";
};

sub xhcpClearErrLog {
  my $clientsock = shift;
  open(FD,'> ./data/error.log');
  close(FD);
  print $clientsock "225 OK\r\n";
};

sub xhcpGetErrLog {
  my $clientsock = shift;
  print $clientsock "207 OK\r\n";
  if (open(FD,'./data/error.log')) {
    my $line = <FD>;
    while (defined($line)) {
      print $clientsock $line;
      $line = <FD>;
    }
    close(FD);
  }
  print $clientsock ".\r\n";
};

1;
