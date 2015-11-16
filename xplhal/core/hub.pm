package xplhal::core::hub;

use strict;
use warnings;

use IO::Socket;
use IO::Select;
use Sys::Hostname;

use xplhal::core::xpl;

use Socket qw(:addrinfo SOCK_RAW);

my (
  $foundport,
  $xpl_socket,
  $msg,
  $fromaddr,
  @localaddr
);

our %hubs = ();

sub broadcastMessage {
  my $ipaddr   = inet_aton('127.0.0.1');
  my $portaddr = sockaddr_in($_[1], $ipaddr);
  my $sockUDP = IO::Socket::INET->new(PeerPort => $_[1],
    Proto => 'udp'
  );
  if (!defined($sockUDP)) {
    print "Error sending xPL message to port $_[1].\n";
    return;
  }  
  $sockUDP->autoflush(1);
  $sockUDP->sockopt(SO_BROADCAST,1);
  $sockUDP->send($_[0],0,$portaddr);  
  close $sockUDP;
}


sub getlocalips {
  my $hostname = Sys::Hostname::hostname();
  my($name, $aliases, $addrtype, $length, @addrs) = gethostbyname($hostname);
  return @addrs;
}

sub isMessageLocal {
  foreach my $ip (@localaddr) {
    if ($ip eq $_[0]) {
      return 1;
    }
  }
  return 0;
}

sub init {
  if ($xplhal::core::prefs::fields->{loadHub} == 1) {
    $xpl_socket = IO::Socket::INET->new(
      Proto     => 'udp',
      LocalPort => 3865,
    );	

    die "The hub could not bind to port 3865. Make sure you are not already running an xPL hub.\nIf you don't want to use the built-in hub, set the loadHub option in the xplhal.xml file to zero." unless $xpl_socket;

    # Get all local IP addresses
    @localaddr = getlocalips();
  print "Hub running.\n";

    defined(xplhal::utils::misc::blocking($xpl_socket,0)) || die "Cannot set port nonblocking";
    xplhal::utils::select::addRead($xpl_socket, \&handlePacket);
  }
}

sub handlePacket {
  my $sock = shift;
  $fromaddr = recv($sock,$msg,1500,0);
  my($port, $ipaddr) = sockaddr_in($fromaddr);

  # Check for heartbeat/config message
  if (xplhal::core::xpl::getmsgtype($msg) eq 'xpl-stat' && xplhal::core::xpl::getmsgschema($msg) =~ "^(config\.(app|end))|(hbeat\.(app|end))") {
    # Is the message local?
    if (isMessageLocal($ipaddr)) {
      $port = xplhal::core::xpl::getparam($msg,"port");
      if (!defined($port)) {
        return;
      }
      # If we've not got it, then add it
      if (!defined($hubs{$port})) {
        $hubs{$port} = xplhal::core::xpl::gethdrparam($msg,"source");
        print "xPL process $hubs{$port} detected on port $port.\n";
      }
      elsif (xplhal::core::xpl::getmsgschema($msg) =~ "^(config\.end)|(hbeat\.end)") {
        # Device is shutting down, so remove it
        delete $hubs{$port};                
      }

    }
  }
  # Broadcast the message to all listening ports
  foreach my $hub (keys %hubs) {
    broadcastMessage($msg,$hub);
  }
};

1;
