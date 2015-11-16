package xplhal::core::globals;

use strict;
use warnings;

use XML::Simple;
use xplhal::core::scripting;

our $globaldata;
my $isDirty;

sub init {
  load();
};

sub load {
  my $FD;
  if (open($FD,'./data/xplhal_globals.xml')) {
    close($FD);
    eval {
      $globaldata = XMLin('./data/xplhal_globals.xml',forcearray=>1,keyattr => []);
    }
  }
  else {
    $globaldata = {};
  }
  $isDirty = 0;
};

sub xhcpDelGlobal {
  my $clientsock = shift;
  my $globalname = shift;
  del($globalname);
  print $clientsock "233 Global deleted\r\n";
};

sub xhcpListGlobals {
  my $clientsock = shift;
  print $clientsock "231 OK\r\n";
  foreach my $global (@{$globaldata->{global}}) {
    print $clientsock "$global->{name}=$global->{value}\r\n";
  }
  print $clientsock ".\r\n";
}

sub xhcpSetGlobal {
  my $clientsock = shift;
  my $cmd = shift;
  my $globalname = substr($cmd,0,index($cmd,' '));
  my $globalvalue = substr($cmd,length($globalname)+1,length($cmd)-length($globalname)-1);
  set($globalname,$globalvalue);
  print $clientsock "232 OK\r\n";
}

sub get {
  my $globalname = uc shift;
  my $globalvalue;

  foreach my $global (@{$globaldata->{global}}) {
    if ($global->{name} eq $globalname) {
      $globalvalue = $global->{value};      
    }
  }
  return $globalvalue;
};

sub xhcpGetGlobal {
  my $clientsock = $_[0];
  my $globalname = uc $_[1];
  my $globalvalue = get($globalname);

  if (defined($globalvalue)) {
    print $clientsock "291 OK\r\n$globalvalue\r\n.\r\n";
  }
  else {
    print $clientsock "491 Invalid global name\r\n";
  }
};

sub del {
  my $globalname = uc shift;
  my @newglobals;
  foreach my $global (@{$globaldata->{global}}) {
    if ($global->{name} ne $globalname) {
    push @newglobals, $global;
    }
  }

  @{$globaldata->{global}} = @newglobals;
  $isDirty = 1;
};

sub set {
  my $globalname = uc shift;
  my $val = shift;

  if (!defined($val)) {
    $val = "";
  }

  # If we already have the global, update it
  my $found = 0;

  foreach my $global (@{$globaldata->{global}}) {
    if ($global->{name} eq $globalname) {
      $found = 1;
      if ($global->{value} ne $val) {
        my $oldval = $global->{value};
        $global->{value} = $val;
      NotifyChange($globalname, $oldval);
      }
    }
  }

  if ($found == 0) {
    my $global = { name => $globalname, value => $val };
    push @{$globaldata->{global}}, $global;
  }

  $isDirty = 1;
};

sub NotifyChange {
  my $globalname = shift;
  my $oldval = shift;
  xplhal::core::scripting::run("$globalname.xpl",$oldval);
  xplhal::core::determinator::processGlobalChange($globalname);
}

sub save {
  if ($isDirty == 0 || !defined($globaldata)) {
    return;
  }

  my $globalxml = XMLout($globaldata);
  if (defined($globalxml)) {
    my $FD;
    open($FD,'> ./data/xplhal_globals.xml');
    print $FD $globalxml;
    close($FD);
  }
};

1;
