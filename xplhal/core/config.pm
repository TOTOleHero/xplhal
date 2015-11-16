package xplhal::core::config;

use xplhal::core::xpl;

my %Devices;

sub init {
  $devices = { };
};

sub handleHeartbeat {
  my $msg = shift;
  my $msg_source = xplhal::core::xpl::gethdrparam($msg,'source');

  if (!defined($devices{$msg_source})) {
    $devices{$msg_source}->{source} = $msg_source;
    $devices{$msg_source}->{interval} = xplhal::core::xpl::getparam($msg,'interval'),
    $devices{$msg_source}->{remoteip} = xplhal::core::xpl::getparam($msg,'remote-ip');
    $devices{$msg_source}->{expires} = time();
    print "Detected xPL device $devices{$msg_source}->{source}.\n";
  }
};

sub xhcpListDevices {
  my $clientsock = shift;
  print $clientsock "216 List of XPL devices follows\r\n";
  foreach my $device (keys %devices) {
    print $clientsock "$devices{$device}->{source}\t\t$devices{$device}->{interval}\tN\tY\t\r\n";
  }  
  print $clientsock ".\r\n";
};
1;
