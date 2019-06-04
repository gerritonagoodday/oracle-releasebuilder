#!/usr/bin/perl

use 5.005_03;
use strict;
use Env;
use Getopt::Long;
use Pod::Usage;
use Term::ANSIColor qw(:constants);
#use File::Basename;
#use DBI qw(:sql_types);
#use Errno;

# global parameters
my ($load_run_id,$file_id,$ad_hoc, @data_file_glob);
# Commandline and configuration parameters
my ($facility,$language,$msgfile,$user,$inst,$pswd,$source_name,$source_file_type,$jap_as_of_date,$data_basis,$debug,$verbose,$quiet,$help,$man,$file_name,$version,$release,$notify);
my $progname=$0;

##############################################################################
# Print information if verbose mode is on
# error is called on a die, so we add a helpful 'Exiting...' message.
sub error   {print RED, @_, "Exiting $progname with error: $!", RESET, "\n";}
sub warning {print BLUE, @_, RESET;}
sub info    {print GREEN, @_, RESET if $verbose;}
sub debug   {print YELLOW, @_, RESET if $debug;}

##############################################################################
# Main
# ~~~~
# Parse commandline parameters
GetOptions( #'instance|i=s'          =>\$inst,
            #'user|u=s'              =>\$user,
            #'password|p=s'          =>\$pswd,
            'facility|f=s'          =>\$facility,
            'language|l=s'          =>\$language,
            'msgfile|m=s'           =>\$msgfile,
            'debug|d'               =>\$debug,
            'verbose'               =>\$verbose,
            'version|v=s'           =>\$version,
            'quiet'                 =>\$quiet,
            'help|?'                =>\$help,
            'man|m'                 =>\$man,
            'release'               =>\$release) ||
pod2usage(-verbose=>1, -exit=>1);
pod2usage(-verbose=>2, -exit=>1) if $help;
pod2usage(-verbose=>3, -exit=>1) if $man;
$verbose=1 if(defined($debug));
if(defined($quiet)){$verbose=0;$debug=0;}

debug '$Header: OracleErrors2FlatFile.pl 1.1 2005/04/05 16:04:15BST ghoekstra PRODUCTION  $',"\n";
if(defined($release)){
  print '$Header: OracleErrors2FlatFile.pl 1.1 2005/04/05 16:04:15BST ghoekstra PRODUCTION  $',"\n";
  exit 1;
}

if(!$facility && !$msgfile){
  pod2usage(-verbose=>0)
}


# Check if environment variables are defined
if(!defined $ENV{ORACLE_HOME}){
  die error("Environment variable ORACLE_HOME is not defined. Exiting...");
}
#if(!defined $ENV{ORACLE_SID}){
#  die error("Environment variable ORACLE_SID is not defined. Exiting...");
#}

# Make up file details if file name has been provided
my $filebasename;
if($msgfile){
  $filebasename=$msgfile;
  $filebasename=~s/\..//g;
  $filebasename=~s/.*\///g;
  $language=$filebasename;
  $language=~s/.+(..)/$1/;
  $facility=$filebasename;
  $facility=~s/(.+)../$1/g;
  if(!$msgfile=~/\//){
    $msgfile=$ENV{ORACLE_HOME}."/rdbms/mesg/$filebasename";
    if(!$msgfile=~/\.msg$/){
      $msgfile="$msgfile.msg";
    }
  }
}else{
  $language='us' if !$language;
  $filebasename=lc("$facility$language");
  $msgfile=$ENV{ORACLE_HOME}."/rdbms/mesg/$filebasename.msg";
}
my $datfile="$filebasename.dat";
$language=uc($language);
$facility=uc($facility);


info("Facility=$facility, Language=$language\n");
info("Reading from $msgfile\n");
open(MSG, $msgfile) ||
  die error("Could not open $msgfile for reading. Exiting...");
  info("Writing to $datfile\n");
open(DAT,"> $datfile") ||
  die error("Could not open $datfile for writing. Exiting...");
print DAT "FACILITY|LANGUAGE|ERROR_CODE|SUBCODE|MESSAGE|CAUSE|ACTION\n";

my ($error_code, $subcode,$message, $cause, $action);
my $count=0;
my $fsm=0;  # simple finite state machine
# 0 Looking for error codes and message
# 1 Looking for "cause"
# 2 Got "cause", looking for "action"
# 3 Got "action"


# Crudely parse
$/ = "\n";
while(<MSG>){
  chomp;
  if(/^\/\/ *(.+)/){    # // ....
    s/\s+\/\/\s+/\\n/g;  # // in the middle of lines need to be new lines
    if($fsm==1){
      if(/\*Cause: +(.+)/){
        $cause=$1;
        $fsm=2;
      }
    }elsif($fsm==2){
      if(/\*Action: +(.+)/){
        $action=$1;
        $fsm=3;
      }else{
        / +(.+)/;
        $cause.="\\n$1";
      }
    }elsif($fsm==3){
        / +(.+)/;
        $action.="\\n$1";
    }
    next;
  }
  if(/^ *(\d+), *(\d+), *"(.+)"/){   # 00000, 00000, "........."
    if($fsm==1 || $fsm==2 || $fsm==3){
      # successive error code lines:
      # write last record
      print DAT "$facility|$language|$error_code|$subcode|$message|$cause|$action\n";
      $count++;
    }
    ($error_code, $subcode,$message)=($1,$2,$3);
    $message=~s/\\n$//; # trim \n from $message
    $cause='';
    $action='';
    $fsm=1;
    next;
  }
  if(/^\/ */){          # / ...
    if($fsm!=0){
      # write last record
      print DAT "$facility|$language|$error_code|$subcode|$message|$cause|$action\n";
      $fsm=0;   # reset fsm to base state
      $count++;
    }
    next;
  }

}

info("Read in $count error messages\n");
close MSG;
close DAT;

__END__

=head1 NAME

OracleErrors2FlatFile - Extacts Oracle error descriptions and explanations from the
message files in $ORACLE_HOME/rdbms/mesg.

This extracts the full canonical details of all Oracle errors, including
information that is not available from the C<sqlcode> and the C<sqlerrm>
SQL functions. The results are typically used for populating the content
of an error management system.

=head1 SYNOPSIS

=over 4

=item C<B<OracleErrors2FlatFile> B<--msgfile> oraus.msg>

Most common format. Creates the file oraus.dat from the file oraus.msg
in the C<$ORACLE_HOME/rdbms/mesg/> directory. The US language ISO code
and the ORA facility code is extracted from the file name.

=item C<B<OracleErrors2FlatFile> B<--facility> ora>

Creates the file oraus.dat from the file $ORACLE_HOME/rdbms/mesg/oraus.msg.
By default the US language file is chosen. Specify other languages with
the --language option using 2-char ISO codes.

=item C<B<OracleErrors2FlatFile> B<--facility> ora B<--language> de>

Creates the file orade.dat from the file $ORACLE_HOME/rdbms/mesg/orade.msg,
which is the German message file for the ORA facility, ja?

=back

=head1 FILE FORMATS

=head2 Input File

These message files are files provided by Oracle. You would only rarely create
your own such files if you were creating a spoken-language translation that is
not supported by Oracle.

=head3 File name

The message file name is in the format

  [facility_code][language].msg

=head3 Directory

By default, the input message file is in the C<$ORACLE_HOME/rdbms/mesg> directory.
If an input file is imported from another directory, then the full file path needs
to be specified using the C<--msgfile> option (see below).

=head3 Data format

The format of the message files is:

    / [comment line]
    [error code],[sub error code], "[message\n]"
    // [optional cause  line 1]
    // [optional cause  line 2] etc...
    // [optional action line 1]
    // [optional action line 2] etc...

Commented lines start with '/ '. The CAUSE section starts with the string C<*Cause:>
and the ACTION section starts with the string C<*Action:>. Note that these section
indicators may vary by spoken language.
The CAUSE and ACTION sections may extend over a number lines. We preserve the carriage
returns with an explicit "\n" string, so that carriage returns can easily identified
and dealt with by the target system.

Various other iniquities in the input file are also dealt with.

=head2 Output File

=head3 File name

A similarly-named flat file with a .dat extension in the
current working directory is created

=head3 Data format

Contains a flattened version of the messages. This is a bar-delimited
flat file with the columns in the header:

   FACILITY|LANGUAGE|ERROR_CODE|SUBCODE|MESSAGE|CAUSE|ACTION

This can be imported to a table using SQL*LDR etc...

=head1 OPTIONS

B<OracleErrors2FlatFile> B<--msgfile> oracle_message_file_name

  or

B<OracleErrors2FlatFile> B<--facility> facility_name

  or

B<OracleErrors2FlatFile> B<--facility> facility_name B<--langauge> iso_code

=head2 Mandatory

=over 4

=item B<-m|--msgfile oracle_message_file_name>

A message file created by messrs. Oracle et al. It usually resides
in the \$ORACLE_HOME/rdbms/mesg directory. If the file should be loaded
from any other location, then specify the file path. If no path has
been specified, then \$ORACLE_HOME should be specified.

OR

=item B<-f|--facility Oracle's facility_name>

Oracle's facility name. This can be derived from the first part of
the message file name. If the language is not specified, then the US
language ISO code is assumed.

=back

=head2 Optional

=over 4

=item B<-l|--language language_iso_code>

The language ISO code that the message file is expected to be in.
This option has to be used in conbination with the --facility option so that
the message file name can be made up. It has to exist in expected directory.

=back

=head1 USING A PERL SCRIPT TO LOAD THE RESULTING ERROR FILE

This is the recommended route to load the data since some of the text
can still be a little 'rough', by creating a SQL script of
insert statements which you can then run on SQL*PLUS.
Configure the C<print> statement to suit your target error table
and the feed the error file to it.

    #!/usr/bin/perl
    while(<>){
      next if $.==1;  # Skip header line
      chomp;
      s/'/''/g;
      s/\\"/"/g;
      s/\\n/\n        /g;
      split /\|/;
      # Deal with ampersants and carriage returns:
      @_[4]=~s/\n/'||chr(10)||\n'/g;
      @_[4]=~s/&/'||chr(38)||'/g;
      @_[5]=~s/\n/'||chr(10)||\n'/g;
      @_[5]=~s/&/'||chr(38)||'/g;
      @_[6]=~s/\n/'||chr(10)||\n'/g;
      @_[6]=~s/&/'||chr(38)||'/g;
      print <<EOF;
    insert into utl.error_codes(ERROR_CODE,MESSAGE,EXPLANATION) values (
    -@_[2],
    '@_[4]',
    'Cause:  @_[5]'||chr(10)||\n'Action: @_[6]');
    EOF
    }



=head1 BACKGROUNDER

=head2 Interesting bits about Oracle Error codes

Oracle assigns a facility code to all its programs. The facility code can be
between 2 an 4 characters long. Refer to the Oracle documentation which program
belongs to which facility.

=head2 More interesting bits about Oracle Error codes

Every Oracle facility has its own set of error codes.
It has been shown that error codes for a given facility can vary by product release -
they certainly vary by platform, although neither case occurs frequently.
If the oerr2file utility is used to create the content of an error management system
then this content should be refreshed when the installation is migrated to a different
version of Oracle or a different platform.

You may now safely destroy your computer and dispose of it in an
environmentally-friendly way.

=cut
