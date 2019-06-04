#!/usr/bin/perl
#----------------------------------------------------------------------------------#
#----------------------------------------------------------------------------------#
# API to build creation scripts of Oracle  objects
#----------------------------------------------------------------------------------#

require 5.006_00;

BEGIN {
  $Oracle::Script::Common::VERSION = "0.01";
}

package Oracle::Script::Common;

use strict;
use Carp qw( croak );
use Term::ANSIColor qw(:constants);
use DBI;
use File::Copy;

#require Exporter;
#use AutoLoader qw(AUTOLOAD);
#our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration use Oracle::DateParse ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.

#our %EXPORT_TAGS = ( 'all' => [qw()] );
#our @EXPORT_OK   = ( @{ $EXPORT_TAGS{'all'} } );
#our @EXPORT      = qw( @CONSTANTS );


#----------------------------------------------------------------------------#
# Print information if verbose mode is on
sub die {
  my $self=shift;
  die RED, @_, RESET, $!;
}
sub warn {
  my $self=shift;
  warn BLUE, @_, RESET;
}
sub info {
  my $self=shift;
  print GREEN, @_, RESET;
}
sub debug {
  my $self=shift;
  print YELLOW, @_, RESET;
}

#----------------------------------------------------------------------------------#
# Get fully-qualified database link name
# This can sometimes return more than one record for the given dblink name, as the
# DBLINK may be represented in terms of all the SQL*Net configurations in use in
# the enterprise by eager DBA's: eg. DBLINK.WORLD and DBLINK.DOMAIN.
# When more than one record is returned, use the current database domain name to select
# the most appropriate one. When the domain name can not be found, then
# the default domain name is will be deemed to be WORLD
#   Parameters: 1. Database connection object
#               2. DBLINK name
#   Returns the fully-qualified DBLINK name
sub get_dblink_full_name{
  my $self=shift;
  my ($connection,$dblink)=@_;
  $dblink=~m/^.+\./;
  my ($owner,$object)=($&,$');
  my $sql="select * ".
          "  from sys.all_db_links ".
          " where db_link like upper(".$connection->quote($object).")||'%' ";
  $sql.=  "   and owner=upper(".$connection->quote($owner).") " if $owner;
  my $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting details for Database Link $dblink.\n".
    "Please log in directly to the database that you want to build scripts for.\n".
    $cursor->errstr()."\n";
  # If we have more than one record describing the database link, then get the domain name
  if($cursor.count()>2){
    $sql="select sys_context(".$connection->quote('userenv').",".$connection->quote('db_domain').") from dual";
    $cursor=$connection->prepare($sql);
    $cursor->execute() || warn "Could not get domain name\n";
    return "$cursor->{1}.$object";
  }else{
    return "$owner.$object";
  }
}

#----------------------------------------------------------------------------------#
# Split 4-part file name "a.b.c.d" into a directory and file "a/b/c.d"
sub file2tree {
  my $self=shift;
  my $file_name =shift;
  # Split file into directory tree
  $file_name=~m/^(.+)\.(.+)\.(.+\..+)/;
  if(!-d $1){
    mkdir($1,0777) || warn "Could not create directory $1. Error: $!\n";
  }
  if(!-d "$1/$2"){
    mkdir("$1/$2",0777) || warn "Could not create directory $1/$2. Error: $!\n";
  }
  move($file_name,qq|$1/$2/$3|) || warn "Could not move temp file $file_name to $1/$2/$3. Error: $!\n";
}

# No need to instantiate this "class"!
#----------------------------------------------------------------------------#
# Parameters:   Argument list as passed from the command line
#sub new {
#  my $type  = shift;
#  my $class = ref($type) || $type;  # Called as $common->new() || Common->new()
#  my $self;
#
#  # Get remaining arguments
#  $self->{arg_list} = join(' ',@_)|| warn "No arguments specified";
#
#  # TODO: Parse arglist
#  # if $self->{arg_list} { ...
#
##  # Bless and return the object.
#  bless $self, $class;
#  return $self;
#}


#----------------------------------------------------------------------------------#
# Prints the contributors and then exits.
sub contributors {
  my $self=shift;
  print <<EOF;
Author: Gerrit Hoekstra <gerrit\@hoekstra.co.uk>
        www.hoekstra.co.uk/opensource
No other contributors so far.
EOF
  exit(0);
}

1;

__END__


=head1 NAME

Oracle::Script::Common - API to build creation scripts of Oracle objects

=head1 SYNOPSIS

This is used as a library component in the script creation modules:

    # script views:
    use Oracle::Script::Common;
    use Oracle::Script::Views;
    my $lib   = new Oracle::Script::Common(@argv);
    my $views = mew Oracle::Script::Views(\$lib);
    $views->ScriptTextFile();

This creates a SQL creation script for the views specified on the command line.

=head1 ABSTRACT

    Oracle::Script::Common is an API to build creation scripts of Oracle objects

=head1 DESCRIPTION

Oracle::Script::Common provides a set of functions common that are used to build
SQL creation scripts of Oracle database objects. The objects that need to be built
are passed in at the creation of this common object. Classes specialising in a
paraticular Oracle object use this common object to create the detailed script.

=head1 USAGE

=head2 new(command line argument string)

    my $lib   = new Oracle::Script::Common(@argv);

=head1 SUPPORTED ORACLE DATE FORMAT ELEMENTS

=over 4

=item B<DD>

Day of month (1-31).

=item B<HH>

Hour of day (1-12).

=item B<HH12>

Hour of day (1-12).

=item B<HH24>

Hour of day (0-23).

=item B<MI>

Minute (0-59).

=item B<MM>

Month (01-12; JAN = 01).

=item B<SS>

Second (0-59).

=item B<YYYY>

4-digit year

=item B<SYYYY>

4-digit year and sign: "-" for BC, "+" for AD.

=back

=head1 UNSUPPORTED ORACLE DATE FORMAT ELEMENTS

Every release attempts to include a few more elements.
Some are impossible to implement.

=over4

=item B<AD,A.D.>

AD indicator with or without periods.

=item B<AM,A.M.>

Meridian indicator with or without periods.

=item B<BC, B.C.>

BC indicator with or without periods.

=item B<CC, SCC>

Century. If the last 2 digits of a 4-digit year are between 01
and 99 (inclusive), then the century is one greater than the first
2 digits of that year. If the last 2 digits of a 4-digit year are 00,
then the century is the same as the first 2 digits of that year.

=item B<D>

Day of week (1-7).

=item B<DAY>

Name of day, padded with blanks to length of 9 characters.

=item B<DDD>

Day of year (1-366).

=item B<DY>

Abbreviated name of day.

=item B<E>

Abbreviated era name (Japanese Imperial, ROC Official, and Thai Buddha calendars).

=item B<EE>

Full era name (Japanese Imperial, ROC Official, and Thai Buddha calendars).

=item B<FF [1..9]>

Fractional seconds; no radix character is printed (use the X format element to
add the radix character). Use the numbers 1 to 9 after FF to specify the number
of digits in the fractional second portion of the datetime value returned.
If you do not specify a digit, then Oracle uses the precision specified for the
datetime datatype or the datatype's default precision.

=item B<IW>

Week of year (1-52 or 1-53) based on the ISO standard.

=item B<IYY, IY I>

Last 3, 2, or 1 digit(s) of ISO year.

=item B<IYYY>

4-digit year based on the ISO standard.

=item B<J>

Julian day; the number of days since January 1, 4712 BC. Number specified with 'J' must be integers.

=item B<MON>

Abbreviated name of month.

=item B<MONTH>

Name of month, padded with blanks to length of 9 characters.

=item B<PM, P.M.>

Meridian indicator with or without periods.

=item B<Q>

Quarter of year (1, 2, 3, 4; JAN-MAR = 1).

=item B<RM>

Roman numeral month (I-XII; JAN = I).

=item B<RR>

Lets you store 20th century dates in the 21st century using only two digits. See "The RR Date Format Element" for detailed information.

=item B<RRRR>

Round year. Accepts either 4-digit or 2-digit input. If 2-digit, provides the same return as RR. If you don't want this functionality, then simply enter the 4-digit year.

=item B<SSSSS>

Seconds past midnight (0-86399).

=item B<TZD>

Daylight savings information. The TZD value is an abbreviated time zone string with daylight savings information. It must correspond with the region specified in TZR.

=item B<TZH>

Time zone hour. (See TZM format element.)

=item B<TZM>

Time zone minute. (See TZH format element.)

=item B<TZR>

Time zone region information. The value must be one of the time zone regions supported in the database.

=item B<WW>

Week of year (1-53) where week 1 starts on the first day of the year and continues to the seventh day of the year.

=item B<W>

Week of month (1-5) where week 1 starts on the first day of the month and ends on the seventh.

=item B<X>

Local radix character.

=item B<Y,YYY>

Year with comma in this position.

=item B<YEAR, SYEAR>

Year, spelled out; "S" prefixes BC dates with "-".

=item B<YYY, YY, Y>

Last 3, 2, or 1 digit(s) of the year.

=back

=head1 HOW IT WORKS

The format string is checked for valid (and supported) format elements.
The format elements are matched against the string to be parsed and matched
Date parts are extacted. The extracted parts populate a Time::Local list.

=head1 SEE ALSO

L<Time::Local|Time::Local>,

L<Date::Transform|Date::Transform>

=head1 TODO

=item [1]   Multiple language support

=item [2]   Multiple epoch support

=item [3]   Timezone support

=item [4]   Other locale-specific issues

=item [5]   Include more of the unsupported format specifiers

=head1 SUPPORT

Please send bug reports or requests for enhancements to the last person
who modified this:

    $Header: Common.pm 1.1 2005/01/31 09:26:41GMT ghoekstra PRODUCTION  $

Alternatively, figure any problems out and send a diff.

=cut
