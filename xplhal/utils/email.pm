package xplhal::utils::email;

use strict;
use warnings;

sub send {
  my $from = shift;
  my $to = shift;
  my $subject = shift;
  my $body = shift;

  open(FD,'> ./data/email.tmp');
  print FD "$body";
  close(FD);
  system("mail -s \"$subject\" $to < ./data/email.tmp");
};

1; 
 