package Apache::DebugInfo;

#---------------------------------------------------------------------
#
# usage: various - see the perldoc below
#
#---------------------------------------------------------------------

use 5.004;
use mod_perl 1.21;
use Apache::Constants qw( OK DECLINED SERVER_ERROR);
use Apache::File;
use Apache::Log;
use Data::Dumper;
use strict;

$Apache::DebugInfo::VERSION = '0.04';

# set debug level
#  0 - messages at info or debug log levels
#  1 - verbose output at info or debug log levels
$Apache::DebugInfo::DEBUG = 0;

sub handler {
#---------------------------------------------------------------------
# this is kinda clunky, but we have to build in some intelligence
# about where the various methods will do the most good
# for those who don't get the apache request cycle
#---------------------------------------------------------------------
  
  my $r           = shift;
  my $log         = $r->server->log;

  return OK unless $r->dir_config('DebugInfo') =~ m/On/i;
 
  $log->info("Using Apache::DebugInfo") if $Apache::DebugInfo::DEBUG;

  my $object = Apache::DebugInfo->new($r);
  
  $object->timestamp;

  $object->headers_in('PerlInitHandler') 
    if $r->dir_config('DebugHeadersIn') =~ m/On/i;
  $object->pid('PerlInitHandler') 
    if $r->dir_config('DebugPID') =~ m/On/i;
  $object->notes('PerlCleanupHandler') 
    if $r->dir_config('DebugNotes') =~ m/On/i;
  $object->pnotes('PerlCleanupHandler') 
    if $r->dir_config('DebugPNotes') =~ m/On/i;
  $object->headers_out('PerlCleanupHandler') 
    if $r->dir_config('DebugHeadersOut') =~ m/On/i;

#---------------------------------------------------------------------
# wrap up...
#---------------------------------------------------------------------

  $log->info("Exiting Apache::DebugInfo") if $Apache::DebugInfo::DEBUG;

  return OK;
}

sub new {
#---------------------------------------------------------------------
# create a new Apache::DebugInfo object
#---------------------------------------------------------------------
  
  my ($class, $r)       = @_;

  my %self              = ();

  my $log               = $r->server->log;

  $self{request}        = $r;
  $self{log}            = $log;

  $self{ip}             = $r->connection->remote_ip;
  $self{uri}            = $r->uri;

  $self{ip_list}        = $r->dir_config('DebugIPList');
  $self{type_list}      = $r->dir_config('DebugTypeList');

  my $file              = $r->dir_config('DebugFile');
  
  $self{fh}             = Apache::File->new(">>$file") if $file;

  if ($file && !$self{fh}) {
    $r->log_error("Can't open $file - $! - using STDERR instead");
    $self{fh} = *STDERR;
  }
  elsif ($self{fh}) {
    $log->info("\tusing $file for output") 
      if $Apache::DebugInfo::DEBUG;
  }
  else {
    $log->info("\tno file specified - using STDERR for output")
      if $Apache::DebugInfo::DEBUG;
    $self{fh} = *STDERR;
  }

  bless(\%self, $class);
 
  return \%self;
}

sub push_on_stack {
#---------------------------------------------------------------------
# add the methods to the various Perl*Handler phases
# this method is for internal use only
#---------------------------------------------------------------------

  my ($self, $debug, @phases) = @_;

  my $r                       = $self->{request};
  my $log                     = $self->{log};

  unless ($self->match_ip && $self->match_type) {
    $log->info("\trequest does not meet critera - skipping")
      if $Apache::DebugInfo::DEBUG;
    return;
  }

  foreach my $phase (@phases) {
    # disable direct PerlHandler calls - it spits Registry scripts
    # to the browser...
    next if $phase =~ m/PerlHandler/;

    $r->push_handlers($phase => sub { $self->$debug() });
    $log->info("\t$phase debugging enabled for \$r->$debug")
      if $Apache::DebugInfo::DEBUG;
   }
   return;
}

sub match_ip {
#---------------------------------------------------------------------
# see if the user's IP matches any given as DebugIPList
# this method is for internal use only
#---------------------------------------------------------------------
 
  my $self              = shift;

  my $r                 = $self->{request};
  my $log               = $self->{log};
  my $ip                = $self->{ip};

  my $ip_list           = $self->{ip_list};

  # return and continue if there is no ip list to check against
  return 1 unless $ip_list;
  
  my @ip_list           = split /\s+/, $ip_list;

  my $total             = 0;

  $log->info("\tchecking $ip against $ip_list")
     if $Apache::DebugInfo::DEBUG;

  foreach my $match (@ip_list) {
    $total++ if ($ip =~ m/\Q$match/);
  }

  return $total;
}

sub match_type {
#---------------------------------------------------------------------
# see if the requested file matches any given in DebugTypeList
# this method is for internal use only
#---------------------------------------------------------------------
 
  my $self              = shift;

  my $r                 = $self->{request};
  my $log               = $self->{log};
  my $ip                = $self->{ip};
  my $uri               = $self->{uri};

  my $type_list         = $self->{type_list};

  # return and continue if there is no type list to check against
  return 1 unless $type_list;
  
  my @type_list         = split /\s+/, $type_list;

  my $total             = 0;

  $log->info("\tchecking $uri against $type_list")
     if $Apache::DebugInfo::DEBUG;

  foreach my $match (@type_list) {
    $total++ if ($uri =~ m/\Q$match\E$/);
  }

  return $total;
}

sub ip {
#---------------------------------------------------------------------
# get or set the ip addresses or subnets for which output will
# be generated
#---------------------------------------------------------------------

  my $self              = shift;
 
  return $self->{ip_list} unless @_;

  my $ip_list           = shift(@_);

  my $log               = $self->{log};

  $self->{ip_list}      = $ip_list;

  $log->info("\twill check client ip address against $ip_list")
     if $Apache::DebugInfo::DEBUG;

  return undef;
}

sub type {
#---------------------------------------------------------------------
# get or set the file extensions for which output will be generated
#---------------------------------------------------------------------

  my $self              = shift;
 
  return $self->{type_list} unless @_;

  my $type_list         = shift(@_);

  my $log               = $self->{log};

  $self->{type_list}    = $type_list;

  $log->info("\twill check requested uri against $type_list")
     if $Apache::DebugInfo::DEBUG;

  return undef;
}

sub file {
#---------------------------------------------------------------------
# get or set the output file
#---------------------------------------------------------------------

  my $self              = shift;

  return $self->{fh} unless @_;
 
  my $file              = shift(@_);

  my $r                 = $self->{request};
  my $log               = $self->{log};

  $self->{fh}           = Apache::File->new(">>$file");

  if ($self->{fh}) {
    $log->info("\tusing $file for output")
       if $Apache::DebugInfo::DEBUG;
  } else {
    $r->log_error("Cannot open file $file - $! - using STDERR instead");
    $self->{fh} = *STDERR;
  }

  return undef;
}

sub timestamp {
#---------------------------------------------------------------------
# print a timestamp to STDOUT
#---------------------------------------------------------------------

  my $self              = shift;

  my @phases            = @_;

  my $log               = $self->{log};
  my $fh                = $self->{fh};

  if (@phases) {
    push_on_stack($self, 'timestamp', @phases);
    $log->info("Exiting Apache::DebugInfo::headers_in") 
      if $Apache::DebugInfo::DEBUG;
    return;
  }

  print $fh "\n**** Apache::DebugInfo - " . scalar(localtime) . "\n"; 

  return undef;
}

sub headers_in {
#---------------------------------------------------------------------
# do some preliminary stuff...
#---------------------------------------------------------------------
  
  my $self              = shift;

  my @phases            = @_;

  my $r                 = $self->{request};
  my $log               = $self->{log};
  my $fh                = $self->{fh};
  my $ip                = $self->{ip};
  my $uri               = $self->{uri};

  $log->info("Using Apache::DebugInfo::headers_in")
     if $Apache::DebugInfo::DEBUG;

#---------------------------------------------------------------------
# if there are arguments, push the routine onto the handler stack
#---------------------------------------------------------------------

  if (@phases) {
    push_on_stack($self, 'headers_in', @phases);
    $log->info("Exiting Apache::DebugInfo::headers_in") 
      if $Apache::DebugInfo::DEBUG;
    return;
  }

#---------------------------------------------------------------------
# otherwise, just print $r->headers_in in a pretty format
#---------------------------------------------------------------------

  my $headers_in = $r->headers_in;

  print $fh "\nDebug headers_in for [$ip] $uri during " .
    $r->current_callback . "\n";

  $headers_in->do(sub {
    my ($field, $value) = @_;
    if ($field =~ m/Cookie/) {
      my @values = split /; /, $value;
      foreach my $cookie (@values) {
        print $fh "\t$field => $cookie\n";
      }
    }
    else { 
      print $fh "\t$field => $value\n";
    }
    1;
  });   

#---------------------------------------------------------------------
# wrap up...
#---------------------------------------------------------------------

  $log->info("Exiting Apache::DebugInfo::headers_in") 
    if $Apache::DebugInfo::DEBUG;

  # return declined so that Apache::DebugInfo doesn't short circuit
  # Perl*Handlers that stop the chain after the first OK (like
  # PerlTransHandler

  return DECLINED;
}

sub headers_out {
#---------------------------------------------------------------------
# do some preliminary stuff...
#---------------------------------------------------------------------
  
  my $self              = shift;

  my @phases            = @_;

  my $r                 = $self->{request};
  my $log               = $self->{log};
  my $fh                = $self->{fh};
  my $ip                = $self->{ip};
  my $uri               = $self->{uri};

  $log->info("Using Apache::DebugInfo::headers_out")
     if $Apache::DebugInfo::DEBUG;

#---------------------------------------------------------------------
# if there are arguments, push the routine onto the handler stack
#---------------------------------------------------------------------

  if (@phases) {
    push_on_stack($self, 'headers_out', @phases);
    $log->info("Exiting Apache::DebugInfo::headers_out") 
      if $Apache::DebugInfo::DEBUG;
    return;
  }

#---------------------------------------------------------------------
# otherwise, just print $r->headers_out in a pretty format
#---------------------------------------------------------------------

  my $headers_out = $r->headers_out;

  print $fh "\nDebug headers_out for [$ip] $uri during " .
    $r->current_callback . "\n";

  $headers_out->do(sub {
    my ($field, $value) = @_;
    if ($field =~ m/Cookie/) {
      my @values = split /;/, $value;
      print $fh "\t$field => $values[0]\n";
      for (my $i=1;$i < @values; $i++) {
        print $fh "\t\t=> $values[$i]\n";
      }
    }
    else { 
      print $fh "\t$field => $value\n";
    }
    1;
  });   

#---------------------------------------------------------------------
# wrap up...
#---------------------------------------------------------------------

  $log->info("Exiting Apache::DebugInfo::headers_out") 
    if $Apache::DebugInfo::DEBUG;

  return DECLINED;
}

sub notes {
#---------------------------------------------------------------------
# do some preliminary stuff...
#---------------------------------------------------------------------
  
  my $self              = shift;

  my @phases            = @_;

  my $r                 = $self->{request};
  my $log               = $self->{log};
  my $fh                = $self->{fh};
  my $ip                = $self->{ip};
  my $uri               = $self->{uri};

  $log->info("Using Apache::DebugInfo::notes")
     if $Apache::DebugInfo::DEBUG;

#---------------------------------------------------------------------
# if there are arguments, push the routine onto the handler stack
#---------------------------------------------------------------------

  if (@phases) {
    push_on_stack($self, 'notes', @phases);
    $log->info("Exiting Apache::DebugInfo::notes") 
      if $Apache::DebugInfo::DEBUG;
    return;
  }

#---------------------------------------------------------------------
# otherwise, just print $r->notes in a pretty format
#---------------------------------------------------------------------

  my $notes = $r->notes;

  print $fh "\nDebug notes for [$ip] $uri during " .
    $r->current_callback . "\n";

  $notes->do(sub {
    my ($field, $value) = @_;
    print $fh "\t$field => $value\n";
    1;
  });   

#---------------------------------------------------------------------
# wrap up...
#---------------------------------------------------------------------

  $log->info("Exiting Apache::DebugInfo::notes") 
    if $Apache::DebugInfo::DEBUG;

  return DECLINED;
}

sub pnotes {
#---------------------------------------------------------------------
# do some preliminary stuff...
#---------------------------------------------------------------------
  
  my $self              = shift;

  my @phases            = @_;

  my $r                 = $self->{request};
  my $log               = $self->{log};
  my $fh                = $self->{fh};
  my $ip                = $self->{ip};
  my $uri               = $self->{uri};

  $log->info("Using Apache::DebugInfo::pnotes")
     if $Apache::DebugInfo::DEBUG;

#---------------------------------------------------------------------
# if there are arguments, push the routine onto the handler stack
#---------------------------------------------------------------------

  if (@phases) {
    push_on_stack($self, 'pnotes', @phases);
    $log->info("Exiting Apache::DebugInfo::pnotes") 
      if $Apache::DebugInfo::DEBUG;
    return;
  }

#---------------------------------------------------------------------
# otherwise, just print $r->notes in a pretty format
#---------------------------------------------------------------------

  my $pnotes = $r->pnotes;

  print $fh "\nDebug pnotes for [$ip] $uri during " .
    $r->current_callback . "\n";

  my %hash = %$pnotes;

  foreach my $field (sort keys %hash) {

    my $value = $hash{$field};
    my $d = Data::Dumper->new([$value]);

    $d->Pad("\t\t");
    $d->Indent(1);
    $d->Quotekeys(0);
    $d->Terse(1);
    print $fh "\t$field => " . $d->Dump;
  }

#---------------------------------------------------------------------
# wrap up...
#---------------------------------------------------------------------

  $log->info("Exiting Apache::DebugInfo::pnotes") 
    if $Apache::DebugInfo::DEBUG;

  return DECLINED;
}

sub pid {
#---------------------------------------------------------------------
# I know this is a waste of code for just printing $$, but I thought
# it would be nice to have a consistent interface.  whatever...
#---------------------------------------------------------------------
  
  my $self              = shift;

  my @phases            = @_;

  my $r                 = $self->{request};
  my $log               = $self->{log};
  my $fh                = $self->{fh};
  my $ip                = $self->{ip};
  my $uri               = $self->{uri};

  $log->info("Using Apache::DebugInfo::pid")
     if $Apache::DebugInfo::DEBUG;

#---------------------------------------------------------------------
# if there are arguments, push the routine onto the handler stack
#---------------------------------------------------------------------

  if (@phases) {
    push_on_stack($self, 'pid', @phases);
    $log->info("Exiting Apache::DebugInfo::pid") 
      if $Apache::DebugInfo::DEBUG;
    return;
  }

#---------------------------------------------------------------------
# otherwise, just print the pid
#---------------------------------------------------------------------

  print $fh "\nDebug pid for [$ip] $uri during " .
    $r->current_callback . "\n\t$$\n";

#---------------------------------------------------------------------
# wrap up...
#---------------------------------------------------------------------

  $log->info("Exiting Apache::DebugInfo::pid") 
    if $Apache::DebugInfo::DEBUG;

  return DECLINED;
}

1;

__END__

=head1 NAME

  Apache::DebugInfo - log various bits of per-request data 

=head1 SYNOPSIS

  There are two ways to use this module...

  1) using Apache::DebugInfo to control debugging automatically

    httpd.conf:

      PerlInitHandler Apache::DebugInfo
      PerlSetVar      DebugInfo On

      PerlSetVar      DebugHeadersIn On
      PerlSetVar      DebugHeadersOut On
      PerlSetVar      DebugNotes On
      PerlSetVar      DebugPNotes On
      PerlSetVar      DebugPID On
 
      PerlSetVar      DebugFile     "/path/to/debug_log"
      PerlSetVar      DebugIPList   "1.2.3.4, 1.2.4."
      PerlSetVar      DebugTypeList ".html .cgi"
    
  2) using Apache::DebugInfo on the fly
    
    in handler or script:

      use Apache::DebugInfo;

      my $r = shift;

      my $debug_object = Apache::DebugInfo->new($r);
 
      # set the output file
      $debug_object->file("/path/to/debug_log");
 
      # get the ip addresses for which output is enabled
      my $ip_list = $debug_object->ip;
 
      # dump $r->headers_in right now
      $debug_object->headers_in;

      # log $r->headers_out after the response goes to the client
      $debug_object->headers_in('PerlCleanupHandler');

      # log all the $r->pnotes at Fixup and at Cleanup
      $debug_object->pnotes('PerlCleanupHandler','PerlFixupHandler');

=head1 DESCRIPTION

  Apache::DebugInfo offers the ability to monitor various bits of
  per-request data.  Its functionality is similar to 
  Apache::DumpHeaders while offering several additional features, 
  including the ability to
    - separate inbound from outbound HTTP headers
    - view the contents of $r->notes and $r->pnotes
    - view any of these at the various points in the request cycle
    - add output for any request phase from a single entry point
    - use as a PerlInitHandler or with direct method calls
    - use partial IP addresses for filtering by IP
    - use file type for filtering
    - offer a subclassable interface
      

  You can enable Apache::DebugInfo as a PerlInitHandler, in which
  case it chooses what request phase to display the appropriate
  data.  The output of data can be controlled by setting various
  variables to On:

    DebugInfo       - enable Apache::DebugInfo handler

    DebugPID        - dumps apache child pid during request init
    DebugHeadersIn  - dumps request headers_in during request init

    DebugHeadersOut - dumps request headers_out during request cleanup
    DebugNotes      - dumps request notes during request cleanup
    DebugPNotes     - dumps request pnotes during request cleanup

  Alternatively, you can control output activity on the fly by
  calling Apache::DebugInfo methods directly (see METHODS below).

  Additionally, the following optional variables hold special
  arguments:

    DebugFile       - absolute path of file that will store the info
                      defaults to STDERR (which is likely error_log)

    DebugIPList     - a space delimited list of IP address for which
                      debugging is enabled
                      this can be a partial IP - 1.2.3 will match
                      1.2.3.5 and 1.2.3.6

    DebugTypeList   - a space delimited list of file extensions
                      for which debugging is enabled

=head1 METHODS

  Apache::DebugInfo provides an object oriented interface to allow you
  to call the various methods from either a module, handler, or an
  Apache::Registry script.

  Constructor:
    new($r)       - create a new Apache::DebugInfo object
                    requires a valid Apache request object

  Methods:
    The following methods can be called without any arguments, in which
    case the associated data is output immediately.  Optionally, each
    can be called with a list (either explicitly or as an array) 
    of Perl*Handlers, which will log the data during the appropriate
    phase.  

    headers_in()  - display all the request incoming HTTP headers
 
    headers_out() - display all the request outgoing HTTP headers

    notes()       - display all the request strings set by $r->notes

    pnotes()      - display all the request variables set by $r->pnotes

    pid()         - display the apache child process PID

    timestamp()   - display the current system time

    There are also the following methods available for manipulating
    the behavior of the above methods:

    file($file)   - get or set the output file
                    accepts an absolute filename as an argument
                    returns the output filehandle
                    overrides DebugFile above

    ip($list)     - get or set the ip list
                    accepts a space delimited list as an argument
                    overrides DebugIPList above

    type($list)   - get or set the file type list
                    accepts a space delimited list as an argument
                    overrides DebugTypeList above

=head1 NOTES

  Verbose debugging is enabled by setting the variable
  $Apache::DebugInfo::DEBUG=1 to or greater.  To turn off all messages
  set LogLevel above info.

  This is alpha software, and as such has not been tested on multiple
  platforms or environments.  It requires PERL_INIT=1, PERL_CLEANUP=1,
  PERL_LOG_API=1, PERL_FILE_API=1, PERL_STACKED_HANDLERS=1, and maybe 
  other hooks to function properly.

=head1 FEATURES/BUGS
  
  Setting DebugInfo to Off has no effect on direct method calls.  

  Once a debug handler is added to a given request phase, it can
  no longer be controlled by ip(), or type(). file(), however, takes
  affect on invocation.  This is becuase matching is done whenever
  the handler is added to the stack, but the output file is used when
  the handler is actually executed.

  Calling Apache::DebugInfo methods with 'PerlHandler' as an argument
  has been disabled - doing so gets your headers and script printed
  to the browser, so I thought I'd save the unaware from potential 
  pitfalls.

  Phase misspellings, like 'PelrInitHandler' pass through without
  warning, in case you were wondering where your output went...

=head1 SEE ALSO

  perl(1), mod_perl(1), Apache(3)

=head1 AUTHOR

  Geoffrey Young <geoff@cpan.org>

=head1 COPYRIGHT

  Copyright 2000 Geoffrey Young - all rights reserved.

  This library is free software; you can redistribute it and/or
  modify it under the same terms as Perl itself.

=cut
