package xplhal::core::prefs;

use strict;

use XML::Simple;

our ($listener_port, $fields, $shortos, $longos);

my $isDirty = 0;

sub init {
  $longos = $^O;
  $shortos = "?";
  mkdir "./data";
  load();
}

sub load {
  my $FD;
  if (open($FD,'./data/xplhal.xml')) {
    close($FD);
    $fields = XMLin('./data/xplhal.xml',forcearray=>1,keyattr => []);
  }
  else {
    # Set defaults
$fields->{listening_address} = "";
$fields->{listening_port} = 3865;
$fields->{loadHub} = 1;
$fields->{enableConfig} = 0;

    $isDirty = 1;
    save();
  }
}

sub save {
  if ($isDirty == 1) {
    my $prefsxml = XMLout($fields);
    my $FD;
    open($FD,'> ./data/xplhal.xml');
    print $FD $prefsxml;
    close($FD);
  }
};

1;