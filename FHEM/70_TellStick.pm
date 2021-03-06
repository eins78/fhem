################################################################
#
#  Copyright notice
#
#  (c) 2012 Copyright: Kai 'wusel' Siering (wusel+fhem at uu dot org)
#  All rights reserved
#
#  This code is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
###############################################

###########################
# 70_TellStick.pm
# Module for FHEM
#
# Contributed by Kai 'wusel' Siering <wusel+fhem@uu.org> in 2012
# Based in part on work for FHEM by other authors ...
# $Id: 70_TellStick.pm 1 2011-11-12 07:51:08Z real-wusel $
###########################

package main;

use strict;
use warnings;


#####################################
sub
TellStick_Initialize($)
{
  my ($hash) = @_;

# Consumer
  $hash->{DefFn}   = "TellStick_Define";
  $hash->{Clients} =
        ":SIS_PMS:";
  my %mc = (
    "1:SIS_PMS"   => "^socket ..:..:..:..:.. .+ state o.*",
  );
  $hash->{MatchList} = \%mc;
  $hash->{AttrList}= "loglevel:0,1,2,3,4,5,6";
  $hash->{ReadFn}  = "TellStick_Read";
  $hash->{WriteFn} = "TellStick_Write";
  $hash->{UndefFn} = "TellStick_Undef";
}



#####################################
sub
TellStick_GetCurrentConfig($)
{
  my ($hash) = @_;
  my $numdetected=0;
  my $currentdevice=0;
  my $FH;
  my $i;
  my $dev = sprintf("%s", $hash->{DeviceName});

  Log 3, "TellStick_GetCurrentConfig: Using \"$dev\" as parameter to open(); trying ...";

  my $tmpdev=sprintf("%s --list 2>&1 |", $dev);
  open($FH, $tmpdev);
  if(!$FH) {
      Log 3, "TellStick_GetCurrentConfig: Can't start $tmpdev: $!";
      return "Can't start $tmpdev: $!";
  }

  local $_;
  while (<$FH>) {
      my $msg=<$FH>;
      chomp($msg);
      my ($devid, $name, $state) = split('\t', $msg);
      Log 3, "TellStick_GetCurrentConfig: read: /$devid/$name/$state/";

      if(defined($devid) && defined($name) && defined($state)) {
	  $numdetected++;
	  Log 3, "TellStick_GetCurrentConfig: $devid $name $state";
      }
  }
  close($FH);
  Log 3, "TellStick_GetCurrentConfig: Initial read done, $numdetected devices found";

  if ($numdetected==0) {
      Log 3, "TellStick_GetCurrentConfig: No TellStick devices found.";
     return "no TellStick or configured devices found.";
  }

  $hash->{NUMDEVS} = $numdetected;
  $hash->{STATE} = "initialized";
  return undef;
}


#####################################
sub
TellStick_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $numdetected=0;
  my $currentdevice=0;
  my $retval;

  return "Define the /path/to/tdtool as a parameter" if(@a != 3);

  my $FH;
  my $dev = sprintf("%s", $a[2]);
  $hash->{DeviceName} = $dev;
  Log 3, "TellStick using \"$dev\" as parameter to open(); trying ...";
 
  $retval=TellStick_GetCurrentConfig($hash);

  Log 3, "TellStick GetCurrentConfing done";

  if(defined($retval)) {
      Log 3, "TellStick: An error occured: $retval";
      return $retval;
  }

  if($hash->{NUMDEVS} < 1) {
      return "TellStick no configured devices found.";
  }

  $hash->{Timer} = 30;

  Log 3, "TellStick setting callback timer";

  my $oid = $init_done;
  $init_done = 1;
  InternalTimer(gettimeofday() + 10, "TellStick_GetStatus", $hash, 1);
  $init_done = $oid;

  Log 3, "TellStick initialized";
  return undef;
}

#####################################
sub
TellStick_Undef($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $hash->{NAME};

  if(defined($hash->{FD})) {
      close($hash->{FD});
      delete $hash->{FD};
  }
  delete $selectlist{"$name.pipe"};

  $hash->{STATE}='undefined';
  Log 3, "$name shutdown complete";
  return undef;
}


#####################################
sub
TellStick_GetStatus($)
{
    my ($hash) = @_;
    my $dnr = $hash->{DEVNR};
    my $name = $hash->{NAME};
    my $dev = $hash->{DeviceName};
    my $FH;
    my $i;

    Log 4, "TellStick contacting device";

    my $tmpdev=sprintf("%s --list", $dev);

    $tmpdev=sprintf("%s 2>&1 |", $tmpdev);
    open($FH, $tmpdev);
    if(!$FH) {
	return "TellStick Can't open pipe: $dev: $!";
    }

    $hash->{FD}=$FH;
    $selectlist{"$name.pipe"} = $hash;
    Log 4, "TellStick pipe opened";
    $hash->{STATE} = "reading";
    $hash->{pipeopentime} = time();
}

#####################################
sub
TellStick_Read($)
{
    my ($hash) = @_;
    my $dnr = $hash->{DEVNR};
    my $name = $hash->{NAME};
    my $dev = $hash->{DeviceName};
    my $FH;
    my $inputline;

    Log 4, "TellStick Read entered";

    if(!defined($hash->{FD})) {
	Log 3, "Oops, TellStick FD undef'd";
	return undef;
    }
    if(!$hash->{FD}) {
	Log 3, "Oops, TellStick FD empty";
	return undef;
    }
    $FH = $hash->{FD};

    Log 4, "TellStick reading started";

    my @lines;
    my $eof;
    my $i=0;
    my $tn = TimeNow();
    my $reading;
    my $readingforstatus;

    ($eof, @lines) = nonblockGetLinesTellStick($FH);

    if(!defined($eof)) {
	Log 4, "TellStick FIXME: eof undefined?!";
	$eof=0;
    }
    Log 4, "TellStick reading ended with eof==$eof";

    # FIXME! Current observed behaviour is "would block", then read of only EOF.
    #        Not sure if it's always that way; more correct would be checking
    #        for empty $inputline or undef'd $rawreading,$val. -wusel, 2010-01-04
    # UPDATE: Seems to work so far, so I'll re-use this as-is ;) -wusel, 2012-01-21
    if($eof != 1) {
	foreach my $inputline ( @lines ) {
	    Log 5, "TellStick read: $inputline";
	    chomp($inputline);
	    my ($devid, $name, $state) = split('\t', $inputline);
	    if(defined($devid) && defined($name) && defined($state)) {
		$state=lc($state);
		my $dmsg = sprintf("socket te:ll:st:ck:01 %d state %s", $devid, $state);
		$name =~ s/\W/_/;
		$hash->{TMPLABEL} = $name;
		Dispatch($hash, $dmsg, undef);
	    } else {
		Log 4, "TellStick line /$inputline/ ignored";
	    }
	}
    }

    if($eof) {
	close($FH);
	delete $hash->{FD};
	delete $selectlist{"$name.pipe"};
	undef($hash->{TMPLABEL});
#	InternalTimer(gettimeofday()+ $hash->{Timer}, "TellStick_GetStatus", $hash, 1);
	$hash->{STATE} = "read";
	Log 4, "TellStick done reading pipe";
    } else {
	$hash->{STATE} = "reading";
	Log 4, "TellStick (further) reading would block";
    }
}


#####################################
sub TellStick_Write($$$) {
    my ($hash,$fn,$msg) = @_;
    my $dev = $hash->{DeviceName};

    my ($serial, $devid, $what) = split(' ', $msg);
    Log 4, "TellStick_Write entered for $hash->{NAME}: $serial, $devid, $what";

    my $cmdline;
    my $cmdletter="l";

    if($what eq "on") {
	$cmdletter="n";
    } elsif($what eq "off") {
	$cmdletter="f";
    }

    $cmdline=sprintf("%s -%s %d 2>&1 >/dev/null", $dev, $cmdletter, $devid);
    system($cmdline);
    Log 4, "TellStick_Write executed $cmdline";
    return;
}


# From http://www.perlmonks.org/?node_id=713384 / http://davesource.com/Solutions/20080924.Perl-Non-blocking-Read-On-Pipes-Or-Files.html
#
# Used, hopefully, with permission ;)
#
# An non-blocking filehandle read that returns an array of lines read
# Returns:  ($eof,@lines)
my %nonblockGetLines_lastTellStick;
sub nonblockGetLinesTellStick {
  my ($fh,$timeout) = @_;

  $timeout = 0 unless defined $timeout;
  my $rfd = '';
  $nonblockGetLines_lastTellStick{$fh} = ''
        unless defined $nonblockGetLines_lastTellStick{$fh};

  vec($rfd,fileno($fh),1) = 1;
  return unless select($rfd, undef, undef, $timeout)>=0;
    # I'm not sure the following is necessary?
  return unless vec($rfd,fileno($fh),1);
  my $buf = '';
  my $n = sysread($fh,$buf,1024*1024);
  # If we're done, make sure to send the last unfinished line
  return (1,$nonblockGetLines_lastTellStick{$fh}) unless $n;
    # Prepend the last unfinished line
  $buf = $nonblockGetLines_lastTellStick{$fh}.$buf;
    # And save any newly unfinished lines
  $nonblockGetLines_lastTellStick{$fh} =
        (substr($buf,-1) !~ /[\r\n]/ && $buf =~ s/([^\r\n]*)$//)
            ? $1 : '';
  $buf ? (0,split(/\n/,$buf)) : (0);
}


1;
