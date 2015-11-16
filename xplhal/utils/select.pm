package xplhal::utils::select;

use IO::Select;

our %readSockets;
my %readCallbacks;

my %writeSockets;
my %writeCallbacks;

my $readSelects = IO::Select->new();
my $writeSelects = IO::Select->new();

sub addRead {
	my $r = shift;
	my $callback = shift;
	if (!$callback) {
		delete $readSockets{"$r"};
		delete $readCallbacks{"$r"};
	} else {
		$readSockets{"$r"} = $r;
		$readCallbacks{"$r"} = $callback;
	}
	$readSelects = IO::Select->new(map {$readSockets{$_}} (keys %readSockets));
}

sub addWrite {
	my $w = shift;
	my $callback = shift;	

	if (!$callback) {
		delete $writeSockets{"$w"};
		delete $writeCallbacks{"$w"};	
	} else {
		$writeSockets{"$w"} = $w;
		$writeCallbacks{"$w"} = $callback;
	}
	$writeSelects = IO::Select->new(map {$writeSockets{$_}} (keys %writeSockets));

}

sub select {
	my $select_time = shift;

	my ($r, $w, $e) = IO::Select->select($readSelects,$writeSelects,undef,$select_time);

					
	my $sock;		
	my $count = 0;
	foreach $sock (@$r) {
		my $readsub = $readCallbacks{"$sock"};
		$readsub->($sock) if $readsub;
		$count++;
	}
	
	foreach $sock (@$w) {
		my $writesub = $writeCallbacks{"$sock"};
		$writesub->($sock) if $writesub;
		$count++;
	}
	return $count;
}

1;
