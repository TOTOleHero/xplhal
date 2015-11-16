package xplhal::core::x10;

use strict;

use XML::Simple;

my $x10data;
my $isDirty;

sub init {
  load();
};

sub load {

  $isDirty = 0;
};

sub save {

};

1;