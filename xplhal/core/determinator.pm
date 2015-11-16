package xplhal::core::determinator;

use strict;
use warnings;
use feature qw/say/;

use Data::Dumper;
use XML::Simple;
use xplhal::utils::misc;

our %determinators;

sub init {
  mkdir "./data/determinator";
  load();
};

sub load {
  opendir(DIR, './data/determinator/') || die "can't opendir determinator: $!";
  my $file = readdir(DIR);
  while (defined($file)) {
    if ($file =~ /^\.\.?$/) {
    }
    else {
      loadDeterminator($file);
    }
    $file = readdir(DIR);
  }
  closedir DIR;
};

sub loadDeterminator {
  my $filename = shift;
  my $determinator = XMLin("./data/determinator/$filename",forcearray=>1,keyattr => []);
  $filename = substr($filename,0,length($filename)-4);

  # Populate some default values if they are missing
  if (!defined($determinator->{determinator}[0]->{enabled})) {
    $determinator->{determinator}[0]->{enabled} = "true";
  }

  $determinators{$filename} = $determinator->{determinator}[0];
};

sub xhcpGetRule {
  my $clientsock = shift;
  my $guid = shift;
  my $filename = "./data/determinator/$guid.xml";
  my $fd;

  if (open($fd,$filename)) {
    binmode($fd); 
    print $clientsock "210 OK\r\n";
    my $file = do { local $/; <$fd> };
    print $clientsock $file; 
    close($fd);
    print $clientsock ".\r\n";
  } else {
  print $clientsock "410 No such rule\r\n";
  }
};

sub xhcpListRules {
  my $clientsock = shift;
  print $clientsock "237 OK\r\n";
  foreach my $determinator (keys %determinators) {
    print $clientsock "$determinator\t$determinators{$determinator}->{name}\t$determinators{$determinator}->{enabled}\r\n";
  }
  print $clientsock ".\r\n";
};

sub xhcpSetRule {
  my $clientsock = shift;
  my $ruleguid = shift;
  my $ruletext = '';
  print $clientsock "338 Continue\r\n";
  my $line = <$clientsock>;
  while (defined($line)) {
    if ($line eq ".\r\n") {
      $line = undef;
    }
    else {
      $ruletext .= $line;
      $line = <$clientsock>;
    }
  }

  if (!defined($ruleguid)) {
    # Create rule GUID
    $ruleguid = (rand 9999) + 10000 + time();
    $ruleguid =~ tr/\./0/;
  }

  open(FD,"> ./data/determinator/$ruleguid.xml");
  print FD $ruletext;
  close(FD);
  print $clientsock "238 OK\r\n";
  loadDeterminator("$ruleguid.xml");
};

sub xhcpDelRule {
  my $clientsock = shift;
  my $ruleguid = shift;
  my $filename = "./data/determinator/$ruleguid.xml";

  unlink $filename;

  if (exists($determinators{$ruleguid})) {
    delete $determinators{$ruleguid};
    print $clientsock "214 OK\r\n";
  } 
  else {
    print $clientsock "410 No such determinator\r\n";
  }
};

sub executeByName {
  # Executes the actions of a determinator
  my $rulename = uc shift;

  # Find the rule in the hash
  foreach my $rule (keys %determinators) {
    if (uc($determinators{$rule}->{name}) eq $rulename) {
      executeByGuid($rule);
    }
  }
};

sub dereference {
  my $val = shift;
  my $msg = shift;  
  my $newval = $val;

  if (index($newval,"{") < 0) {
    return $newval;
  }

  # First replace globals
  my $Now = xplhal::utils::misc::currentTime();
  $newval =~ s/{now}/$Now/gi;
  foreach my $global (@{$xplhal::core::globals::globaldata->{global}}) {
    $newval =~ s/{\Q$global->{name}\E}/$global->{value}/gi;
  }

  if (!defined($msg)) {
    return $newval;
  }

  my %params = xplhal::core::xpl::getparams($msg);  

  foreach my $param (keys %params) {
    my $ucparam = uc($param);
    $newval =~ s/{XPL::$ucparam}/$params{$param}/g;
  }

  return $newval;
};

sub executeByGuid {
  my $guid = shift;
  my $msg = shift;
  my $determinator = $determinators{$guid};

  if (!defined($determinator)) {
    xplhal::utils::misc::debug "Determinator with GUID $guid not found.";
    return 0;
  }

  # Check determinator is enabled
  if (uc $determinator->{enabled} ne "Y") {
    return;
  }

  # Check conditions
  foreach my $condition (%{$determinator->{input}->[0]}) {
    if ($condition eq "match") {
    } else {
      foreach my $conditiontype (@{$determinator->{input}->[0]->{$condition}}) {
        if ($condition eq "globalCondition") {
          my $val = xplhal::core::globals::get($conditiontype->{name});
          if (!defined($val)) {
            return;
          } elsif ($conditiontype->{operator} eq "=" && uc($val) ne uc($conditiontype->{value})) {
            return;
          }
        }
      }
    }
  }

  # Loop through all actions
  my $counter = 0;
  my $ruleExists;
  do {
$ruleExists = 0;
  foreach my $action (%{$determinator->{output}->[0]}) {
    foreach my $actiontype (@{$determinator->{output}->[0]->{$action}}) {
if ($actiontype->{executeOrder} == $counter) {
  $ruleExists = 1;
    if ($action eq 'delayAction') {    
      sleep $actiontype->{delay_seconds};
    } elsif ($action eq 'globalAction') {    
      xplhal::core::globals::set($actiontype->{name},dereference($actiontype->{value},$msg));
    } elsif ($action eq 'logAction') {
      xplhal::utils::misc::writeErrorLog($actiontype->{logText});
    } elsif ($action eq 'xplAction') {
      my $sendmsg = '';
      # Add parameters
      foreach my $actionparam (@{$actiontype->{xplActionParam}}) {
        my $deref = dereference($actionparam->{expression},$msg);
        $sendmsg .= "$deref\n";
      }
      $sendmsg = substr($sendmsg,0,length($sendmsg)-1);
      xplhal::core::xpl::sendxplmsg("xpl-$actiontype->{msg_type}","$actiontype->{msg_target}","$actiontype->{msg_schema}",$sendmsg);
      }
}
    }
  }
  $counter++;
  } while ($ruleExists==1);
};

sub xhcpRunRule {
  my $clientsock = shift;
  my $rulename = shift;
  executeByGuid($rulename);
  print $clientsock "203 OK\r\n";
};

sub checkGlobalRule {
  my $guid = shift;
  my $globalName = shift;
  my $determinator = $determinators{$guid};

  my @conditions = $determinator->{input}[0]->{globalChanged};

  if (!$conditions[0]) {
    return;
  }

  for (my $i=0; $i < @conditions; $i++) {
    if (uc($conditions[$i][0]->{name}) eq uc($globalName)) {
      executeByGuid($guid);
      return;
    }
  }

}

sub processGlobalChange {
  my $globalName = shift;

  foreach my $guid (keys %determinators) {
    checkGlobalRule($guid, $globalName);
  }
}

sub processMessage {
  my $msg = shift;

  foreach my $guid (keys %determinators) {
    checkRule($guid, $msg);
  }
};

sub checkRule {
  my $guid = shift;
  my $msg = shift;
  my $msg_type = xplhal::core::xpl::getmsgtype($msg);
  my $msg_source =  xplhal::core::xpl::gethdrparam($msg,'source');
  my ($msg_source_vendor, $msg_source_device, $msg_source_instance) = $msg_source =~ /^(\w+)-(\w+)\.(\w+)$/x;
  my $msg_target =  xplhal::core::xpl::gethdrparam($msg,'target');
  my ($msg_target_vendor, $msg_target_device, $msg_target_instance) = $msg_target =~  /^(\w+)-(\w+)\.(\w+)$/x;
  my $msg_schema =  xplhal::core::xpl::getmsgschema($msg);
  my ($msg_schema_class, $msg_schema_type) = $msg_schema =~ /^(\w+)\.(\w+)$/x;
  my $determinator = $determinators{$guid};
  my $execute = 0;

  # If target is *, set everything to *
  if (!defined($msg_target_vendor)) {
    $msg_target_vendor = $msg_target_device = $msg_target_instance = "*";
  }

  if (!defined($determinator)) {
    return;
  }

  my @conditions = $determinator->{input}[0]->{xplCondition};

  if (!$conditions[0]) {
    return;
  }

  for (my $i=0; $i < @conditions; $i++) {
    $execute = 1;
    # First check message type
    if (uc("xpl-$conditions[$i][0]->{msg_type}") ne uc($msg_type)) {
      $execute = 0;
    }
    # Now check source
    if (uc($conditions[$i][0]->{source_vendor}) ne uc($msg_source_vendor) && $conditions[$i][0]->{source_vendor} ne "*") {
      $execute = 0;
    }
    if (uc($conditions[$i][0]->{source_device}) ne uc($msg_source_device) && $conditions[$i][0]->{source_device} ne "*") {
      $execute = 0;
    }
    if (uc($conditions[$i][0]->{source_instance}) ne uc($msg_source_instance) && $conditions[$i][0]->{source_instance} ne "*") {
      $execute = 0;
    }
    # Now check target
    if (uc($conditions[$i][0]->{target_vendor}) ne uc($msg_target_vendor) && $conditions[$i][0]->{target_vendor} ne "*") {
      $execute = 0;
    }
    if (uc($conditions[$i][0]->{target_device}) ne uc($msg_target_device) && $conditions[$i][0]->{target_device} ne "*") {
      $execute = 0;
    }
    if (uc($conditions[$i][0]->{target_instance}) ne uc($msg_target_instance) && $conditions[$i][0]->{target_instance} ne "*") {
      $execute = 0;
    }
    # Now check schema
    if (uc($conditions[$i][0]->{schema_class}) ne uc($msg_schema_class) && $conditions[$i][0]->{schema_class} ne "*") {
      $execute = 0;
    }
    if (uc($conditions[$i][0]->{schema_type}) ne uc($msg_schema_type) && $conditions[$i][0]->{schema_type} ne "*") {
      $execute = 0;
    }    

    # Now check parameters
    if (defined($conditions[$i][0]->{param})) {
  my $k = 0;
  while (defined($conditions[$i][0]->{param}->[$k])) {
        my $val = xplhal::core::xpl::getparam($msg,$conditions[$i][0]->{param}->[$k]->{name});
        my $operator = $conditions[$i][0]->{param}->[$k]->{operator};

        if (!defined($val)) {
          $execute = 0;
        }

        if ($operator eq "=") {
          if (!defined($val) || uc($val) ne uc($conditions[$i][0]->{param}->[$k]->{value})) {
            $execute = 0;
          }
        } else {
          $execute = 0;
        }
$k++;
      }
    }

    if ($execute==1) {
      # Execute
      executeByGuid($guid, $msg);
    }
  }
};

1;
