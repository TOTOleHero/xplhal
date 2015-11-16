package xplhal::utils::misc;

use strict;

use Socket;
use Time::HiRes;
use Symbol qw(qualify_to_ref);

BEGIN {
        if ($^O =~ /Win32/) {
                *EWOULDBLOCK = sub () { 10035 };
                *EINPROGRESS = sub () { 10036 };
        } else {
                require Errno;
                import Errno qw(EWOULDBLOCK EINPROGRESS);
        }
}

sub blocking {   
  my $sock = shift;
  return $sock->blocking(@_) unless $^O =~ /Win32/;
  my $nonblocking = $_[0] ? "0" : "1";
  my $retval = ioctl($sock, 0x8004667e, \$nonblocking);
  if (!defined($retval) && $] >= 5.008) {
    $retval = "0 but true";
  }
  return $retval;
};

sub sysreadline(*;$) { 
	my($handle, $maxnap) = @_;
	$handle = qualify_to_ref($handle, caller());

	return undef unless $handle;

	my $infinitely_patient = @_ == 1;

	my $start_time = Time::HiRes::time();

	my $selector = IO::Select->new();
	$selector->add($handle);

	my $line = '';
	my $result;

#	print STDOUT "GIMME A LINE\n";
#	bt();
SLEEP:
	until (at_eol($line)) {
		unless ($infinitely_patient) {
			if (Time::HiRes::time() > $start_time + $maxnap) {
#				print "Sorry, Charlie, time's up!\n";
				return $line;
			} 
		} 
		my @ready_handles;

		unless (@ready_handles = $selector->can_read(.1)) {  # seconds
#			print STDOUT "STILL SLEEPING at ", scalar(localtime()), "...sleeping ";
			unless ($infinitely_patient) {
				my $time_left = $start_time + $maxnap - Time::HiRes::time();
#				print "no more than $time_left more seconds";
			} else {
#				print "until you're darned good and ready";
			} 
#			print "\n";
			next SLEEP;
		}

INPUT_READY:
		while (() = $selector->can_read(0.0)) {

			my $was_blocking = blocking($handle,0);

CHAR:       while ($result = sysread($handle, my $char, 1)) {
				$line .= $char;
				last CHAR if $char eq "\n";
			} 
			my $err = $!;
			blocking($handle, $was_blocking);

			unless (at_eol($line)) {
				if (!defined($result) && $err != EWOULDBLOCK) { 
#					print "WARNING: error: $err in sysread during syslineread\n";
					return undef;					
				}
#				printf "WARNING: Incomplete line (%s) result: $result, err: $err still trying\n", $line;
				next SLEEP;
			} 
#			printf "Got line from fd#%d: <<%s>>\n", $handle->fileno, $line;
			last INPUT_READY;
		}
	} 
	return $line;
};

# this function based on a posting by Tom Christiansen: http://www.mail-archive.com/perl5-porters@perl.org/msg71350.html
sub at_eol($) { $_[0] =~ /\n\z/ };

sub currentHour {
  my ($second, $minute, $hour, $day, $month, $year, $weekDay, $dayOfYear, $IsDST) = localtime(time);
  return $hour;
};

sub currentMinute {
  my ($second, $minute, $hour, $day, $month, $year, $weekDay, $dayOfYear, $IsDST) = localtime(time);
  return $minute;
};

sub currentTime {
  my $t = shift;

  if (!defined($t)) {
    $t = time;
  }

  my ($second, $minute, $hour, $day, $month, $year, $weekDay, $dayOfYear, $IsDST) = localtime($t);
  $month = $month + 1;
  if ($month < 10) {
    $month = "0" . $month;
  }
  if ($day < 10) {
    $day = "0" . $day;
  }
  if ($hour < 10) {
    $hour = "0" . $hour;
  }
  if ($minute < 10) {
    $minute = "0" . $minute;
  }

  if ($second < 10) {
    $second = "0" . $second;
  }

  $year = $year + 1900;
  return "$day/$month/$year $hour:$minute:$second";
};

sub debug {
  writeErrorLog($_[0]);
};

sub writeErrorLog {
  my $logtext = shift;

  if (!defined($logtext)) {
    return;
  }

  my $timestamp = currentTime();
  open(FD,'>> ./data/error.log');
  print FD "$timestamp $logtext\r\n";
  close(FD);
  print "$logtext\n";
};

1;
