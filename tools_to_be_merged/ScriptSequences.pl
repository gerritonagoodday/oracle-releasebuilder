#!/usr/bin/perl
#----------------------------------------------------------------------------------#
#----------------------------------------------------------------------------------#
# FUNCTION:
# Scripts the creation scripts of Oracle Sequences into nice installation files.
#----------------------------------------------------------------------------------#
# Copyright (c) 1999-2005 Gerrit Hoekstra. Alle Rechte vorbehalten.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details. <www.gnu.org>
#
# If you use this program to provide publicly available output, please
# give us some form of credit in the results. If you can improve the way
# this script does something, fix it and send us a diff please. Your efforts
# will be noted in subsequent releases.
# Visit www.hoekstra.co.uk/opensource for the most recent version.
#----------------------------------------------------------------------------------#

use 5.8.0;
use strict;
use DBI;
use DBD::Oracle qw(:ora_session_modes);
use Getopt::Long;
use Pod::Usage;
use File::Copy;
use Oracle::Script::FileHeaders;
use Oracle::Script::Common;


#----------------------------------------------------------------------------------#
# Globals
my $file_name;                      # Table creation File name
my $sql;                            # SQL String
my @row;                            # Result set
my $dbh;                            # DB connection
my $mode=0;                         # DB Connection mode
my @schema_objects;
my $cmd;
my $object_owner;
my $object_name;
my $ignore_empty;
my $year = ((localtime())[5]+1900); # Copyright Year
my $start_time=time();              # Start time
my $file_count=0;                   # File counter
my $one_shot=0;                     # One shot flag
my $two_shot=0;                     #

# Command Line parameters
my ($instance,$meta_schemas,@meta_schemas,$meta_types,@objects,$userid,$password,$author,$verbose,$contributors,$version_display,$debug,$excel,$dblink,$quiet,$man,$help,$gnu,$grants,$no_storage);

#----------------------------------------------------------------------------------#
# Prints the version of this script and exits the program
sub version_display{
  print '$Header: ScriptSequences.pl 1.1 2005/01/31 09:31:37GMT ghoekstra DEV  $'."\n";
  exit(0);
}

#----------------------------------------------------------------------------------#
# Get all details for type
sub get_object_details{
  my ($connection,$cursor,$owner,$object)=@_;
  my $sql="select distinct * ".
          "  from sys.all_sequences".(defined($dblink)?'\@'.$dblink:'').
          " where sequence_name=upper(".$connection->quote($object).") ".
          "   and sequence_owner=upper(".$connection->quote($owner).") ";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting details of $owner.$object".(defined($dblink)?'\@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get Table Grantees
# TODO: for types
#sub get_type_grantees{
#  my ($connection,$cursor,$owner,$object)=@_;
#  my $sql=  "select GRANTEE ".
#                " , count(*) as grant_count ".
#             " from sys.all_tab_privs".(defined($dblink)?'\@'.$dblink:'').
#            " where table_schema = ".$connection->quote($owner).
#              " and table_name = ".$connection->quote($object).
#            " group by GRANTEE ".
#            " order by 1";
#  $cursor=$connection->prepare($sql);
#  $cursor->execute() || die "Error getting table grantees for table $owner.$object".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
#  return $cursor;
#}

#----------------------------------------------------------------------------------#
# Get Table Grants
# TODO: for types
#sub get_type_grants{
#  my ($connection,$cursor,$owner,$object,$grantee)=@_;
#  my $sql=  "select * ".
#             " from sys.all_tab_privs".(defined($dblink)?'\@'.$dblink:'').
#            " where grantee = ".$connection->quote($grantee).
#              " and table_schema = ".$connection->quote($owner).
#              " and table_name = ".$connection->quote($object).
#            " order by privilege";
#  $cursor=$connection->prepare($sql);
#  $cursor->execute() || die "Error getting table grants for table $owner.$object".(defined($dblink)?'@'.$dblink:'')." grantee $grantee.\n".$cursor->errstr()."\n";
#  return $cursor;
#}

#----------------------------------------------------------------------------------#
# Checks if table exists
sub does_object_exist{
  my ($connection,$cursor,$owner,$object)=@_;
  my $sql="select distinct sequence_owner, sequence_name ".
          "  from sys.all_sequences".(defined($dblink)?'\@'.$dblink:'').
          " where sequence_owner=upper(".$dbh->quote($owner).") ".
          "   and sequence_name=upper(".$dbh->quote($object).") ".
          " order by 1,2";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error checking if table $owner.$object exists.\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get all scriptable tables for the string of schemas
sub get_scriptable_objects{
  my ($connection,$cursor,$schemas)=@_;
  my $sql=
      "select distinct sequence_owner, sequence_name".
      "  from sys.all_sequences".(defined($dblink)?'\@'.$dblink:'').
      " where instr(upper(".$dbh->quote($schemas)."),sequence_owner) <> 0".
      " order by sequence_owner,sequence_name";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting all scriptable objects for the string of schemas [$schemas].\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Script to text file
sub ScriptTextFile{
  my @schema_objects=@_;
  # We now have a list of all the tables which to create CREATION scripts for:
  foreach (@schema_objects){
    my $owner=$_->{"schema"};
    my $object=$_->{"object"};
    # Get all details for the object
    my $c_object;
    $c_object=get_object_details($dbh, $c_object, $owner, $object);
    my $object_row_ref=$c_object->fetchrow_hashref();
    die "Failed to retrieve details of $owner.$object".(defined($dblink)?'@'.$dblink:'') if(!defined $object_row_ref->{SEQUENCE_OWNER});

    # Make up file name
    my $short_file_name=lc($object).".sql";
    my $file_name = lc($owner).".sequences.".lc($object).".sql";
    Oracle::Script::Common->info("Building creation script for sequence $owner.$object".(defined($dblink)?'@'.$dblink:'')." in file $short_file_name\n") if(!$quiet);
    open(F,"+>".$file_name) || die "Could not open temporary file $file_name for writing. $!\n";
    $file_count++;
    print F Oracle::Script::FileHeaders->MakeSQLFileHeader($file_name,$owner,$author,$dblink);
    print F "-- Creation script for sequence $owner.$object\n--\n";
    print F Oracle::Script::FileHeaders->OracleDBDetails($userid,$password,$instance);
    print F "-- To run this script from the command line:\n";
    print F "-- sqlplus $owner/[password]\@[instance] \@$short_file_name\n";
    print F "------------------------------------------------------------------------------\n";
    print F "set feedback off;\n";
    print F "prompt Creating sequence $owner.$object\n";
    print F "\n";
    print F "-- Drop type if it already exists\n";
    print F "-- Note that the contents of the table will also be deleted.\n";
    print F "declare \n";
    print F "  v_count integer=0;\n";
    print F "begin\n";
    print F "  select count(*)\n";
    print F "    into v_count\n";
    print F "    from sys.all_objects\n";
    print F "   where object_type = 'SEQUENCE'\n";
    print F "     and owner = upper('".$owner."')\n";
    print F "     and object_name = upper('".$object."');\n";
    print F "  if(v_count>0)then\n";
    print F "    execute immediate 'drop sequence $owner.$object';\n";
    print F "  end if;\n";
    print F "end;\n";
    print F "/\n";

    # Begin creation script
    print F "------------------------------------------------------------------------------\n";
    print F "-- Create sequence\n";
    print F "------------------------------------------------------------------------------\n";
    print F "\n";
    print F "create sequence $owner.$object\n";
    print F "  minvalue $object_row_ref->{MIN_VALUE} \n";
    print F "  maxvalue $object_row_ref->{MAXVALUE}\n";
    print F "  increments by $object_row_ref->{INCREMENTS_BY}\n";
    if($object_row_ref->{CYCLE_FLAG} eq 'Y'){
      print F "  cycle\n";
    }else{
      print F "  nocycle\n";                          # Default
    }
    if($object_row_ref->{CACHE_SIZE} > 0){            # Default (20)
      print F "  cache $object_row_ref->{CACHE_SIZE}\n";
    }else{
      print F "  nocache\n";
    }
    if($object_row_ref->{ORDER_FLAG} eq 'Y'){
      print F "  order\n";
    }else{
      print F "  noorder\n";                             # Default
    }
    print F ";\n";
    print F "\n";

    # Priviledges
    # Only include them if explicitly required - there is another scripts that will centrally create all grants
    # TODO
#    if($grants){
#      $one_shot=0;
#      my $c_grantees;
#      $c_grantees=get_type_grantees($dbh,$c_grantees,$owner,$object);
#      my $tg_row_ref;
#      while($tg_row_ref=$c_grantees->fetchrow_hashref()){
#        if($one_shot==0){
#          $one_shot=1;
#          print F " \n";
#          print F "------------------------------------------------------------------------------\n";
#          print F "-- Grant/Revoke privileges\n";
#          print F "------------------------------------------------------------------------------\n";
#        }
#        if($tg_row_ref->{GRANT_COUNT}>=7){
#          # Full house: we can say "grant all"
#          $sql="grant all";
#        }else{
#          # Show selection of grant for this grantee
#          $two_shot=0;
#          $sql="grant ";
#          my $c_grants;
#          $c_grants=get_type_grants($dbh,$c_grants,$owner,$object,$tg_row_ref->{GRANTEE});
#          my $tgr_row_ref;
#          while($tgr_row_ref=$c_grants->fetchrow_hashref()){
#            if($two_shot==0){
#              $two_shot=1;
#            }else{
#              $sql.=', ';
#            }
#            $sql.=$tgr_row_ref->{PRIVILEGE};
#          }
#        }
#        $sql.=" on $owner.$object to $tg_row_ref->{GRANTEE};\n";
#        print F $sql;
#      }
#    }

    # Finish File
    print F Oracle::Script::FileHeaders->MakeSQLFileFooter($file_name);
    close F;

    if($debug){
       # Display file to stdout
       open(F,"<".$file_name)||die "Could not open $file_name for display. $!\n";
       my @lines=<F>;
       close F;
       foreach(@lines){Oracle::Script::Common->debug("$_");}
    }


    # Split file into directory tree
    Oracle::Script::Common->file2tree($file_name,$short_file_name);
  }
}

#----------------------------------------------------------------------------------#
# Main Program
GetOptions( 'instance|i=s'=>\$instance,
            'user|u=s'    =>\$userid,
            'password|p=s'=>\$password,
            'dblink|l=s'  =>\$dblink,
            'schemas|s=s' =>\@meta_schemas,
            'objects|o=s' =>\@objects,
            'debug|d'     =>\$debug,
            'grants|g'    =>\$grants,
            'no-storage'  =>\$no_storage,
            'ignoreempty' =>\$ignore_empty,
            'author=s'    =>\$author,
            'contributors'=>\$contributors,
            'version|v'   =>\$version_display,
            'verbose'     =>\$verbose,
            'gnu'         =>\$gnu,
            'spreadsheet|x'=>\$excel,
            'quiet'       =>\$quiet,
            'help|?'      =>\$help,
            'man'         =>\$man) || pod2usage(2);
pod2usage(-exitstatus => 0, -verbose => 1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Override parameters
if(defined $contributors){contributors();}
if(defined $version_display){version_display();}

# Mandatory parameter
if(!defined $instance){
  if(!defined $ENV{ORACLE_SID}){
    warn "Database Instance must be specified";
    pod2usage(-exitstatus=>1, -verbose=>0);
  }else{
    $instance=$ENV{ORACLE_SID};
  }
}
if(!defined $userid  ){
  warn "Database UserId must be specified";
  pod2usage(-exitstatus=>1, -verbose=>0);
}
if(!defined $password){
  warn "Database Password must be specified";
  pod2usage(-exitstatus=>1, -verbose=>0);
}

# Clean up parameters
$meta_schemas=join(',',@meta_schemas);
$meta_schemas=~s/\s//;
$meta_schemas=~tr/a-z/A-Z/;
$meta_types=join(',',@objects);
$meta_types=~s/\s//;
$meta_types=~tr/a-z/A-Z/;
$verbose=1 if($debug);

# Connect to the database
Oracle::Script::Common->info("Connecting to Database $instance...") if($verbose);
$dbh = DBI->connect("dbi:Oracle:$instance", $userid, $password, {ora_module_name=>$0, ora_session_mode=>$mode})
  || die "Unable to connect to $instance: $DBI::errstr\n";
Oracle::Script::Common->info("Connected.\n") if($verbose);

# We want dates to appear in nice text form
#$dbh->do("ALTER SESSION SET NLS_DATE_FORMAT = 'YYYYMMDDHH24MISS'")
#  || Oracle::Script::Common->warn("You have no access rights to ALTER SESSION SET NLS_DATE_FORMAT. Will use the current format.\n");

# Anticipate long values when dealing with Oracle data dictionary
$dbh->{LongReadLen} = 512 * 1024;
$dbh->{LongTruncOk} = 1;

if(defined($dblink)){
  $dblink=Oracle::Script::Common->get_dblink_full_name($dbh,$dblink);
}

# -o parameter:
# Get all individually specified tables
if($meta_types){
  my @spec_objects=split(/,/,$meta_types);
  foreach my $object(@spec_objects){
    my @schema_object=split(/\./,$object);
    # Where no schema name is defined, default to the user login schema
    if(!exists $schema_objects[1]){
      push(@schema_object,@schema_object[0]);
      @schema_object[0]=$userid;
    }
    print "Individually specified type: ",uc(@schema_object[0].@schema_object[1]),"\n" if($verbose);
    # Check if this table exists
    my $cursor;
    $cursor=does_object_exist($dbh,$cursor,@schema_object[0],@schema_object[1]);
    # Fetch single record
    @row=$cursor->fetchrow_array();
    if(scalar(@row)==0){
      die "Individually specified object ",uc(@schema_object[0].@schema_object[1])," does not exist or should not scripted.\n";
    }else{
      push(@schema_objects,{"schema"=>uc(@schema_object[0]),"object"=>uc(@schema_object[1])});
    }
    $cursor->finish();
  }
}

# -s parameter:
# Get all schemas for which table create scripts will be created, if any schemas are defined at all
# You may have specified other schemas, but either they don't exist or they don't have any tables in them
if($meta_schemas){
  # Get all the tables that belong to the schemas
  my $cursor;
  $cursor=get_scriptable_objects($dbh,$cursor,$meta_schemas);
  my $objects_ref = $cursor->fetchall_arrayref();
  foreach my $row(@{$objects_ref}){
    my ($schema,$object) = @{$row};
    push(@schema_objects,{"schema"=>$schema,"object"=>$object});
  }
  $cursor->finish();
}

# Default, if no schemas or tables have been defined
if(!$meta_types && !$meta_schemas){
  print "Creating initialisation scripts for all tables in schema $userid.\n" if($verbose);
  # Get all the tables that belong to the schemas
  my $cursor;
  $cursor=get_scriptable_objects($dbh,$cursor,$userid);
  my $objects_ref = $cursor->fetchall_arrayref();
  foreach my $row(@{$objects_ref}){
    my ($schema,$object) = @{$row};
    push(@schema_objects,{"schema"=>$schema,"object"=>$object});
  }
  $cursor->finish();
}

# Remove duplicate items from @schema_objects
my $last;
my @schema_objects_;
foreach (sort {$a->{"schema"}.".".$a->{"object"} <=> $b->{"schema"}.".".$b->{"object"}} @schema_objects){
  if($last ne $_->{"schema"}.".".$_->{"object"}){
    push(@schema_objects_,{"schema"=>$_->{"schema"},"object"=>$_->{"object"}});
  }
  $last=$_->{"schema"}.".".$_->{"object"};
}
@schema_objects=@schema_objects_;

#if($excel){
#  ScriptSpreadsheet(@schema_objects);
#}else{
  ScriptTextFile(@schema_objects);
#}

END:{
# Disconnect
  if(defined $dbh){
    Oracle::Script::Common->info("Disconnecting...") if($verbose);
    $dbh->disconnect() || Oracle::Script::Common->warn("Failed to disconnect from $instance. ".$dbh->errstr()."\n");
    Oracle::Script::Common->info("done.\n") if($verbose);
  }
  my $proc_time=time()-$start_time;
  Oracle::Script::Common->info("Created $file_count file(s) in $proc_time seconds.\n") if(!$quiet);
  exit(0);
}

__END__

=head1 NAME

ScriptSequences.pl - Generates formal creation scripts for Oracle data types

=head1 SYNOPSIS

=over 4

=item B<ScriptSequences.pl> B<-i> db1 B<-u> user B<-p> passwd

Builds the creation scripts for all the sequences in the schema 'user' on
database instance db1.

=item B<ScriptSequences.pl> B<-i> db1 B<-u> user B<-p> passswd B<-m> schema1 B<-m> schema2

Builds the creation scripts only for all the sequences in the schemas 'schema1'
and 'schema2' on database instance db1. Use this form if the required schema
does not have select rights to SYS.ALL_... views, and use a system user to log
with.

=item B<ScriptSequences.pl> B<-i> db1 B<-u> user B<-p> passwd B<-t> schema1.table1

Builds the creation scripts only for the sequence 'schema1.table1' on database
instance db1.

=item B<ScriptSequences.pl> B<-i> db1 B<-u> user B<-p> passwd -l db2

Builds the creation scripts for all the sequences in the DBLink's default schemas
of the remote database instance, which is accessed from this database instance
db1 via database link db2.

=item B<ScriptSequences.pl> B<-i> db1 B<-u> user B<-p> passwd B<-m> schema1,schema2 B<-l> db2

Builds the creation scripts for all the sequences in the schemas 'schema1'
and 'schema2' on a remote database instance that is accessed from this
Oracle instance db1 via the database link db2.

=item B<ScriptSequences.pl> B<--help>

Provides detailed description.

=back

=head1 OPTIONS AND ARGUMENTS

B<ScriptSequences.pl> B<-u|--user> UserId B<-p|--password> Passwd [B<-i|--instance> Instance name]
[-l|--dblink DBLink] [-s|--schemas Schemas] [-o|--objects Types] [--no-storage]
[-g|--grants] [--IgnoreEmpty] [-x|--spreadsheet] [--contributors] [-v|--version]
[--author author name] [--gnu] [--quiet|--verbose|--debug] [-?|--help] [--man]

=head2 Mandatory

=over 4

=item B<-i|--instance Oracle Database instance name>

Specify the TNS name of the Oracle Database instance, unless the environment
variable ORACLE_SID is set to the desired instance.

=item B<-u|--user User login Id>

User / schema login Id

=item B<-p|--password Password>

Password to accompany the login Id

=back

=head2 Optional

=over 4

=item B<-l|--dblink Database link>

Database link Id to a remote database. If the required schema on the
remote database does not have select rights to its SYS.ALL_... views,
get your DBA to grant remote DBlink user select access to these views.
It is helpful to specify the fully-qualified link name (e.g. DBLINK.DOMAIN).
If no domain is specified, the default WORLD domain will be assumed.

=item B<-s|--schemas List of schema names>

Schema name(s) for which the types will be scripted out.
Either use -m schema1 -m schema2 or -m schema1,schema2.

=item B<-o|--objects List of data type names>

Object(s) belonging to the logged in schema or the DB Link's default schema.
You may specify a different schema name using the [schema].[object] notation.
Either use -o object1 -o object2 or -t object1,object2.

=item B<-g|--grants Script grants>

By default grant scripts are not included since there is another script that
will centrally create these. Set this flag if you explicitly require them in
this script.

=item B<--no_storage>

Do not specify any table storage parameters

=item B<--ignoreempty>

Ignore empty types - e.g. those with no body

=item B<-x|--spreadsheet>

Create a Spreadsheet report of the objects

=item B<--author>

Your company or your name for optional copyright notice. A commercial or the
GNU license (if you specify the --gnu option) will be included in the header
of every generated file.

=item B<--gnu>

The GNU license will be included in the header of every generated file,
asserting copyright to the specified author (if you specified the --author option).

=item B<--contributors>

List of contributors

=item B<-v|--version>

Current Version details of this script.

=item B<--quiet|--verbose|--debug>

No console output at all | Verbose output to STDOUT | Debug mode with even
more output to STDOUT

=item B<-?|--help>

Displays simple help

=item B<--man>

Displays this in a man-page format.

=back

=head1 DESCRIPTION

Generates object creation scripts for Oracle 8 and upwards.
This has been tested with version 8, 9 and 10 databases.

This script forms part of a suite of scripts to create a managable
text-based Oracle installation that can easily integrate into any
version control system.

This product avoids the use of complex and proprietory tools, installs
easily on most operating systems that support Perl, and occupies a small footprint.

This script creates a output files in a directory tree based off the current
directory (e.g. the directory that you are running this script from). Output
files will be arranged in the form schema_name/object_type/object_name.sql,
where the object types are tables, metadata, sequences, packages, functions,
procedures, exceptions, views, type and triggers.

You can run the resulting scripts individually from SQLPLUS or the console
to create the objects on an Oracle instance:

    $ sqlplus "sys/[password]@[instance] as sysdba" @[script]

=head2 FILE OUTPUT

A separate file will be created for every database object, which will be
given the name of the database object and a .sql file extension.
Each generated files will contain a file header and a file footer.

B<File header>

This will note information about the database that the script was generated from.
If an author name was specified (--Author option), it will also be included.
If the --GNU option was specified, the standard GNU license will also be included.

B<File footer>

This will be a simple terminating line and an End of File statement.

B<Date format>

Dates will be displayed in the format C<YYYYMMDDHH24MISS> where possible.

=head1 REQUIREMENTS

=head2 All operating systems

B<1.> The scripts in this suite will run on Unix, Solaris, Linux and
WIN32 clients, as long as there is a TNS-name entry pointing to valid Oracle
database somewhere on the network.

B<2.> Install Perl if it is not already on your development environment.
This is likely to be the case if you are running this from a Windows
environment. See Note for Windows Users below.

B<3.> Install the DBI and DBD::Oracle packages from CPAN if you have
not already done so - they are not included with most Perl distributions,
and you will need a C/C++-compiler like gcc. If this is the first time that
CPAN is run on the client machine, then you need to go through a short
Q&A-based configuration first. From the console:

    # perl -MCPAN -e shell

Once CPAN is configured, you can install DBI from with the CPAN shell:

    cpan> install DBI

After this is successfully completed, install the Oracle driver for DBI.
To do this, you need to have an Oracle instance already running on the network,
you should have the TNS-name entry set up on your client and the account
SCOTT/TIGER should be unlocked and accessible from the client:

    cpan> install DBD:Oracle

Finally, you need to install the Spreadsheet::WriteExcel module if you want
to generate Excel-type spreadsheet output:

    cpan> install Spreadsheet::WriteExcel

You can check if you installed all this correctly:

    # perl -MDBI -e 'DBI->installed_versions'

=head2 Note for Windows Users

B<1.> Currently, the best Windows release of Perl can be
found at www.activeperl.com. In fact, this release of Perl
is good for any operating system.

B<2.> In Windows, the file associations to .pl file should
supercede any existing associations for .pl files, otherwise you
will not be able to pass parameters to a perl file from the
commmand line. This will be set for you when you install ActivePerl.

B<3.> Add the following key to your registry:

    HKEY_LOCAL_MACHINE\SOFTWARE\Perl: "lib"="c:\oracle\tools"

or wherever you are running these scripts from. Also put this directory
in your path.

B<4.> You need to install the DBI and DBD::Oracle modules:
If you have installed ActivePerl, you do not need to get CPAN up and running and
you can install the modules as follows by opening up a console and typing:

    c:\> ppm
    ppm> install DBI
    ppm> install DBD-Oracle

B<5.> You also need to install the Spreadsheet::WriteExcel module if you want
to generate Excel-type spreadsheet output:

    ppm> install Spreadsheet-WriteExcel

B<6.> If you do want to run CPAN from Windows (you may need to if the above ppm-install
did not work), download the collection of Unix utilities for Windows from
www.hoekstra.co.uk/opensource, and put them somewhere in your path.

B<7.> You will also need a C/C++ compiler and a make utility.
Use cl.exe and nmake.exe from MS Visual Studio 6 or 7. Ensure that
C:\Program Files\Microsoft Visual Studio\VC98\bin is on your path,
(or wherever you have installed Visual Studio) so that nmake.exe and cl.exe
are visible. Note that this will not work with Visual Studio .Net 2002/2003!

B<8.> Change the following lines manually in  C:\Perl\lib\CPAN\Config.pm from:

    'make' => q[C:\Program Files\Microsoft Visual Studio\VC98\bin\nmake.EXE]

to:

    'make' => q["C:\Program Files\Microsoft Visual Studio\VC98\bin\nmake.EXE"]

...or wherever you have installed Visual Studio.

=head1 INSTALLATION

Put this package somewhere in your perl @INC path.
To see the value of @INC path from the command line:

    # perl -e 'print join(qq|\n|,@INC),"\n";'

=head1 BUGS

None so far.

=head1 TODO

B<1.> Turn this into a CPAN component.

B<2.> Sort out creation script & allocation of memory.

=head1 ALTERNATIVES

You can try the following methods for very accurate results but without the
nice formatting:

=head2 Using Oracle9i++ DBMS_METADATA package:

From the SQLPLUS shell, type:

    SQL> connect <table_owner>
    SQL> select dbms_metadata.get_ddl('<OBJECT>','<object name>') from dual;

=head2 Using Oracle's EXP and IMP utilties:

This is only supported for some objects, such as tables in the example below.
Refer to the Oracle Utilities documentation for more details.

    # exp userid=<user> tables=<tablename> rows=n
    # imp userid=<user> fully indexfile=<tablename.sql>
    # sed -e '/^REM  //' < tablename.sql > tablename.sql.tmp
    # mv tablename.sql.tmp tablename.sql

=head1 AUTHOR

This code was written by Gerrit Hoekstra I<E<lt>gerrit@hoekstra.co.ukE<gt>>.

=head1 CONTRIBUTING

If you use this program to provide publicly available output, please give
some form of credit in the results. If you can improve the way this script
does something, fix it and send a diff please. Your efforts will be noted
in subsequent releases. Visit www.hoekstra.co.uk/opensource for the most
recent version.

=head1 LICENSE

Copyright (c) 1999-2005 Gerrit Hoekstra. Alle Rechte vorbehalten.
This is free software; see the source for copying conditions. There is NO warranty;
not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

=cut

