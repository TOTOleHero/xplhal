package xplhal::core::xpl;

use strict;

use IO::Socket;
use IO::Socket::INET;
use Time::HiRes qw ( usleep );
use Sys::Hostname;
use xplhal::core::config;
use xplhal::core::determinator;

my (
  $heartbeat_count,
  $xpl_socket,
  $localip
);

our $xpl_source;

sub init {
  my $FD;
  $heartbeat_count = ($xplhal::utils::constants::heartbeat_interval*6);

  # Read the source from source.cfg if it exists
  if (open($FD,'./data/source.cfg')) {
    $xpl_source = <$FD>;
    close($FD);
  }
  else {
    my $computername = validInstance(hostname);
    $xpl_source = "XPL-XPLHAL.$computername";
    open($FD,'> ./data/source.cfg');
    print $FD $xpl_source;
    close($FD);
  }

  if (defined($xplhal::core::prefs::fields->{listening_address}) && $xplhal::core::prefs::fields->{listening_address} ne "") {
$localip = $xplhal::core::prefs::fields->{listening_address};
  } else {
$localip = get_local_ip_address();
  }
  # Bind to a listener port
  my	$xpl_port = 50000;
  while (!$xpl_socket && $xpl_port < 50200) {
    $xpl_socket = IO::Socket::INET->new(
			Proto     => 'udp',
			LocalPort => $xpl_port,
			LocalAddr => $main::localClientNetAddr
    );	
    if (!$xpl_socket) {
			$xpl_port = $xpl_port + 1;
    }
  }
  defined(xplhal::utils::misc::blocking($xpl_socket,0)) || die "Cannot set port nonblocking";
  die "Could not create socket: $!\n" unless $xpl_socket;
  xplhal::utils::select::addRead($xpl_socket, \&readxpl);
  $xplhal::core::prefs::listener_port = $xpl_port;
  print "Listening on $localip port $xpl_port\n";
};

sub sendHeartbeat {
  $heartbeat_count++;

  if ($heartbeat_count > ($xplhal::utils::constants::heartbeat_interval*6)) {
    sendxplmsg('xpl-stat','*','hbeat.app',"interval=$xplhal::utils::constants::heartbeat_interval\nport=$xplhal::core::prefs::listener_port\nremote-ip=$localip");
    $heartbeat_count = 0;
  }
}

sub sendxplmsg {
  # Generic routine for sending an xPL message.
  my $msg;
  $msg = "$_[0]\n{\nhop=1\nsource=$xpl_source\ntarget=$_[1]\n}\n$_[2]\n{\n$_[3]\n}\n";
  my $ipaddr   = inet_aton('255.255.255.255');
  my $portaddr = sockaddr_in(3865, $ipaddr);
  my $sockUDP = IO::Socket::INET->new(PeerPort => 3865,
                                   Proto => 'udp'
      );
  
  $sockUDP->autoflush(1);
  $sockUDP->sockopt(SO_BROADCAST,1);
  $sockUDP->send($msg,0,$portaddr);  
  close $sockUDP;
  usleep(50000);
}

sub validInstance {
# This routine ensures an xPL instance is valid
# by removing any invalid characters and trimming to
# 16 characters.
	my $instance = $_[0];
	$instance =~ s/(-|\.|!|;)//g;
	if (length($instance) > 16) {
		$instance = substr($instance,0,16);
	}
	return $instance;
}

sub readxpl {
  # Processes an incoming xPL message
  my $sock = shift;
  my $msg;

  recv($sock,$msg,1500,0);

  my $msg_type = getmsgtype($msg);
  my $msg_source = gethdrparam($msg,'source');
  my $msg_target = gethdrparam($msg,'target');
  my $msg_schema = getmsgschema($msg);

  # Pass the message to the Determinators module for processing
  xplhal::core::determinator::processMessage($msg, $msg_type, $msg_target, $msg_schema);

  # Pass the message to the scripting module for processing
  xplhal::core::scripting::processMessage($msg, $msg_source, $msg_schema);  

  # Handle command messages
  if ($msg_type eq 'xpl-cmnd') {
    # Handle messages targetted at me
    if (uc($msg_target) eq uc($xpl_source)) {
      # config.list
      if ($msg_schema eq 'config.list') {
        if (defined(getparam($msg,'command')) && getparam($msg,'command') eq 'request') {
          sendxplmsg('cmnd','*','config.list',"reconf=newconf\noption=interval");
        }
      }
      # config.current
      if ($msg_schema eq 'config.current') {
        if (defined(getparam($msg,'command')) && getparam($msg,'command') eq 'request') {
        }
      }
      # config.response
      if ($msg_schema eq 'config.response') {
        if (getparam($msg,'command') eq 'request') {
        }
      }
    }
  } elsif ($msg_type eq "xpl-stat") {
    # Look for heartbeats and pass them to the device config module
    if ($msg_schema =~ /^hbeat/) {
      xplhal::core::config::handleHeartbeat($msg);
    }
  }
};

sub xhcpSendXplMsg {
  my $clientsock = shift;
  print $clientsock "313 Continue\r\n";
  my $msg = '';
  my $line = <$clientsock>;
  while (defined($line)) {
    if ($line eq ".\r\n") {
      $line = undef;
    }
    else {
      $line = substr($line,0,length($line)-2);
      $msg .= "$line\n";
      $line = <$clientsock>;
    }
  }
  sendxplmsg($msg);
  print $clientsock "213 OK\r\n";
};

sub getparams {
	my $buff = $_[0];  
	$buff = substr($buff,index($buff,"}"),length($buff)-index($buff,"}"));
	$buff = substr($buff,index($buff,"{")+2,length($buff)-index($buff,"{")-2);
	$buff = substr($buff,0,index($buff,"}")-1);
	my %params = map { split /=/, $_, 2 } split /\n/, $buff ;
  return %params;
};

sub getparam {
  if (!defined($_[1])) {
    return undef;
  }

# Retrieves a parameter from the body of an xPL message
  my %params = getparams($_[0]);
	return $params{$_[1]};
}

sub gethdrparam {
  # Retrieves a parameter from the header of an xPL message
  my $buff = $_[0];  
  $buff = substr($buff,index($buff,"{")+2,length($buff)-index($buff,"{")-2);
  $buff = substr($buff,0,index($buff,"}")-1);
  my %params = map { split /=/, $_, 2 } split /\n/, $buff ;
  return $params{$_[1]};
}

sub getmsgtype {
# Returns the type of an xPL message, e.g. xpl-stat, xpl-trig or xpl-cmnd
	return lc substr($_[0],0,8);
}

sub getmsgschema {
  # This routine accepts an xPL message and returns the message schema, in lowercase characters
	my $buff = $_[0];
	$buff = substr($buff,index($buff,"}")+2,length($buff)-index($buff,"}")-2);
	$buff = substr($buff,0,index($buff,"\n"));
	return lc $buff;
}

# This idea was stolen from Net::Address::IP::Local::connected_to()
sub get_local_ip_address {
    my $socket = IO::Socket::INET->new(
        Proto       => 'udp',
        PeerAddr    => '198.41.0.4', # a.root-servers.net
        PeerPort    => '53', # DNS
    );

    # A side-effect of making a socket connection is that our IP address
    # is available from the 'sockhost' method
    my $local_ip_address = $socket->sockhost;

    return $local_ip_address;
}

1;
