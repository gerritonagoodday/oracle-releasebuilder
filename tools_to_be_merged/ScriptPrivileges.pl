#!/usr/bin/perl
#----------------------------------------------------------------------------------#
#----------------------------------------------------------------------------------#
# FUNCTION:
# Creates formal Package creation scripts
#----------------------------------------------------------------------------------#
# Copyright (c) 1999-2005 Gerrit Hoekstra
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

#----------------------------------------------------------------------------------#
use strict;
use DBI;
use DBD::Oracle qw(:ora_session_modes);
use Getopt::Long;
use File::Copy;
use Pod::Usage;
use Oracle::Script::FileHeaders;
use Oracle::Script::Common;

#----------------------------------------------------------------------------------#
# Globals
# Command Line parameters
my ($instance,$meta_schemas,@meta_schemas,$meta_objects,@objects,$userid,$password,$author,$verbose,$contributors,$version_display,$debug,$excel,$dblink,$quiet,$man,$help,$gnu);
my $file_name;                      # creation File name
my $sql;                            # SQL String
my @row;                            # Result set
my $dbh;                            # DB connection
my $mode=0;                         # DB Connection mode
my @meta_schemas;
my @schema_objects;
my @objects;
my $cmd;
my $ignore_empty;
my $year = ((localtime())[5]+1900); # Copyright Year
my $start_time=time();              # Start time
my $file_count=0;                   # File counter
my $one_shot=0;                     # One shot flag
my $two_shot=0;                     #

#----------------------------------------------------------------------------------#
# Prints the version of this script and exits the program
sub version_display{
  print '$Header: ScriptPrivileges.pl 1.1 2005/01/31 09:29:06GMT ghoekstra DEV  $'."\n";
  exit(0);
}

#----------------------------------------------------------------------------------#
# Get schemas for which grants can be created for a given list of schemas
sub get_scriptable_objects{
  my ($connection,$cursor,$owners)=@_;
  my $sql="select distinct".
          "       grantee ".
          "  from sys.all_tab_privs".(defined($dblink)?'\@'.$dblink:'').
          " where instr(upper(".$dbh->quote($owners)."),grantee) <> 0".
          " union ".
          "select distinct".
          "       grantor".
          "  from sys.all_tab_privs".(defined($dblink)?'\@'.$dblink:'').
          " where instr(upper(".$dbh->quote($owners)."),grantor) <> 0 ".
          " order by 1";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting all scriptable objects for the string of schemas $owners.\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get Grantees
sub get_grantees{
  my ($connection,$cursor,$owners)=@_;
  my $sql="select distinct ".
          "       grantee ".
          "  from sys.all_tab_privs".(defined($dblink)?'@'.$dblink:'').
          " where instr(upper(".$dbh->quote($owners)."),grantee) <> 0".
          " union ".
          "select distinct ".
          "       grantor ".
          "  from sys.all_tab_privs".(defined($dblink)?'@'.$dblink:'').
          " where instr(upper(".$dbh->quote($owners)."),grantor) <> 0 ".
          " order by 1";
    $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting grantees for $owners".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get all system privileges
sub get_system_privileges{
  my ($connection,$cursor,$owners)=@_;
  my $sql="select distinct ".
          "       privilege".
          "     , admin_option".
          "     , grantee".
          "  from sys.dba_sys_privs".(defined($dblink)?'@'.$dblink:'').
          " where instr(upper(".$dbh->quote($owners)."),grantee) <> 0".
          " order by grantee,privilege";
    $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting system privieges for schemas $owners".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get all object privileges granted to this schema
# Makes: grant c.privilege on c.owner.c.table_name to c.grantee;
sub get_schemas_object_privileges{
  my ($connection,$cursor,$owners)=@_;
  my $sql="select distinct".
          "       t.grantee,".
          "       t.privilege,".
          "       t.table_schema,".
          "       t.table_name,".
          "       t.grantable,".
          "       decode(o.object_type,".
          "              'PACKAGE','PACKAGE',".
          "              'PACKAGE BODY','PACKAGE',".
          "              o.object_type) as object_type".
          "  from sys.all_tab_privs".(defined($dblink)?'@'.$dblink:'')." t".
          " inner join sys.all_objects".(defined($dblink)?'@'.$dblink:'')." o".
          "    on o.owner = t.table_schema".
          "   and o.object_name = t.table_name".
          " where instr(upper(".$dbh->quote($owners)."),grantee) <> 0".
          " order by 1,2,3,4,5,6";
    $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting object privileges granted to $owners".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get all object privileges owned by specified schemas to others
sub get_others_object_privileges{
  my ($connection,$cursor,$owners)=@_;
  my $sql="select distinct".
          "       t.grantee,".
          "       t.privilege,".
          "       t.table_schema,".
          "       t.table_name,".
          "       t.grantable,".
          "       decode(o.object_type,".
          "             'PACKAGE','PACKAGE',".
          "             'PACKAGE BODY','PACKAGE',".
          "             o.object_type) as object_type".
          "  from sys.all_tab_privs".(defined($dblink)?'@'.$dblink:'')." t".
          " inner join sys.all_objects".(defined($dblink)?'@'.$dblink:'')." o".
          "    on o.owner = t.table_schema".
          "   and o.object_name = t.table_name".
          " where instr(upper(".$dbh->quote($owners)."),t.grantor) <> 0".
          "   and instr(upper(".$dbh->quote($owners)."),t.grantee) = 0".
          " order by 1,2,3,4,5,6";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error object privileges owned by $owners to others".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Script to text file
sub ScriptTextFile{
  my $owners = shift;

  # Make up file name
  my $file_name="privileges.sql";
  Oracle::Script::Common->info("Building privilege creation scripts in file $file_name\n") if(!$quiet);
  open(F,"+>".$file_name) || die "Could not open file $file_name for writing. $!\n";
  $file_count++;
  print F Oracle::Script::FileHeaders->MakeSQLFileHeader($file_name,$userid,$author,$dblink);
  print F "-- Privilege creation script for schemas\n";
  print F "-- $owners\n--\n";
  print F Oracle::Script::FileHeaders->OracleDBDetails($userid,$password,$instance);
  print F "-- To run this script from the command line:\n";
  print F "-- sqlplus \"sys/[password]\@[instance] as sysdba\" $file_name\n";
  print F "------------------------------------------------------------------------------\n";
  print F "set serveroutput on size 1000000\n";
  print F "set pagesize 0\n";
  print F "set verify off\n";
  print F "set feedback off\n";
  print F "spool log/%ORACLE_SID%_privileges.log\n";
  print F "\n";

  my $last_grantee;
  my $sql;

  if($mode==ORA_SYSDBA){
    print F  "------------------------------------------------------------------------------\n";
    print F  "prompt SYSTEM Privileges\n";
    print F  "------------------------------------------------------------------------------\n";
    $last_grantee='@';
    my $c_sys_privs;
    $c_sys_privs= get_system_privileges($dbh,$c_sys_privs,$owners);
    my $c_sp;
    while($c_sp->fetchrow_hashref()){
      if($last_grantee ne $c_sp->{GRANTEE}){
        $last_grantee=$c_sp->{GRANTEE};
        print F "\n";
        print F "prompt SYSTEM Privileges granted to $c_sp->{GRANTEE}:\n";
      }
      $sql="grant $c_sp->{PRIVILEGE} to $c_sp->{GRANTEE}";
      if($c_sp->{ADMIN_OPTION}='YES'){
        $sql.=" with admin option";
      }
      print F "$sql;\n";
    }
    print F  "\n";
  }

  print F  "------------------------------------------------------------------------------\n";
  print F  "prompt Object Privileges\n";
  print F  "------------------------------------------------------------------------------\n";
  $last_grantee='@';
  my $c_object_privs;
  $c_object_privs=get_schemas_object_privileges($dbh,$c_object_privs,$owners);
  my $c_tp;
  while($c_tp=$c_object_privs->fetchrow_hashref()){
    if($last_grantee ne $c_tp->{GRANTEE}){
      $last_grantee=$c_tp->{GRANTEE};
      print F  " \n";
      print F  "prompt Object Privileges granted to $c_tp->{GRANTEE}:\n";
    }
    if($c_tp->{OBJECT_TYPE} eq 'DIRECTORY'){
      $sql = "grant $c_tp->{PRIVILEGE} on directory $c_tp->{TABLE_SCHEMA}.$c_tp->{TABLE_NAME} to $c_tp->{GRANTEE}";
    }else{
      $sql = "grant $c_tp->{PRIVILEGE} on $c_tp->{TABLE_SCHEMA}.$c_tp->{TABLE_NAME} to $c_tp->{GRANTEE}";
    }
    if($c_tp->{GRANTABLE} eq 'YES'){
      $sql.=" with grant option";
    }
    print F  "$sql;\n";
  }
  print F  " \n";


  $last_grantee='@';
  my $c_grantor_privs;
  $c_grantor_privs=get_others_object_privileges($dbh,$c_grantor_privs,$owners);
  my $c_tp;
  while($c_tp=$c_grantor_privs->fetchrow_hashref()){
    if($last_grantee ne $c_tp->{GRANTEE}){
      $last_grantee=$c_tp->{GRANTEE};
      print F  " \n";
      print F  "prompt $owners-owned Object Privileges granted to $c_tp->{GRANTEE}:\n";
    }
    if($c_tp->{OBJECT_TYPE} eq 'DIRECTORY'){
      $sql = "grant $c_tp->{PRIVILEGE} on directory $c_tp->{TABLE_SCHEMA}.$c_tp->{TABLE_NAME} to $c_tp->{GRANTEE}";
    }else{
      $sql = "grant $c_tp->{PRIVILEGE} on $c_tp->{TABLE_SCHEMA}.$c_tp->{TABLE_NAME} to $c_tp->{GRANTEE}";
    }
    if($c_tp->{GRANTABLE} eq 'YES'){
      $sql.=" with grant option";
    }
    print F  "$sql;\n";
  }

  print F  "\n";
  print F  "spool off\n";
  print F  "\n";

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
}


#----------------------------------------------------------------------------------#
# Main Program
GetOptions( 'instance|i=s'=>\$instance,
            'user|u=s'    =>\$userid,
            'password|p=s'=>\$password,
            'dblink|l=s'  =>\$dblink,
            'schemas|s=s' =>\@meta_schemas,
            'debug|d'     =>\$debug,
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
}else{
  $mode=ORA_SYSDBA if($userid=~m/sys /i);
}
if(!defined $password){
  warn "Database Password must be specified";
  pod2usage(-exitstatus=>1, -verbose=>0);
}

# Clean up parameters
$meta_schemas=join(',',@meta_schemas);
$meta_schemas=~s/\s//;
$meta_schemas=~tr/a-z/A-Z/;
$meta_objects=join(',',@objects);
$meta_objects=~s/\s//;
$meta_objects=~tr/a-z/A-Z/;
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

# -s parameter:
# Get all schemas for which object create scripts will be created, if any schemas are defined at all
# You may have specified other schemas, but either they don't exist or they don't have any objects in them
if($meta_schemas){
  print "Extracting privileges for the following schemas:\n" if($verbose);
  # Get all the objects that belong to the schemas
  my $cursor;
  $cursor=get_scriptable_objects($dbh,$cursor,$meta_schemas);
  my $objects_ref = $cursor->fetchall_arrayref();
  foreach my $row(@{$objects_ref}){
    my $schema = @{$row}[0];
    print "Schema ".lc($schema)."\n" if($verbose);
    push(@schema_objects,{"owner"=>$schema});
  }
  $cursor->finish();
}

# Default, if no schemas or objects have been defined
if(!$meta_objects && !$meta_schemas){
  print "Extracting privileges for the default schema\n" if($verbose);
  # Get all the objects that belong to the schemas
  my $cursor;
  $cursor=get_scriptable_objects($dbh,$cursor,$userid);
  my $objects_ref = $cursor->fetchall_arrayref();
  foreach my $row(@{$objects_ref}){
    my ($schema) = @{$row};
    print "Schema ".lc($schema)."\n" if($verbose);
    push(@schema_objects,{"owner"=>$schema});
  }
  $cursor->finish();
}

# Remove duplicate items from @schema_objects
my $last;
my @schema_objects_;
foreach (sort {$a->{"owner"}<=>$b->{"owner"}} @schema_objects){
  if($last ne $_->{"owner"}){
    push(@schema_objects_,{"owner"=>$_->{"owner"}});
  }
  $last=$_->{"owner"};
}
@schema_objects=@schema_objects_;


my @owners;
foreach (@schema_objects){
  push @owners, $_->{"owner"};
}

ScriptTextFile(join(',',@owners));

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

ScriptPrivileges.pl - Generates formal Privilege creation script

=head1 SYNOPSIS

=over 4

=item B<ScriptPrivileges.pl> B<-i> db1 B<-u> user B<-p> passwd

Builds the creation scripts for all the packages in the schema 'user' on
database instance db1.

=item B<ScriptPrivileges.pl> B<-i> db1 B<-u> user B<-p> passswd B<-m> schema1 B<-m> schema2

Builds the creation scripts only for all the packages in the schemas 'schema1'
and 'schema2' on database instance db1. Use this form if the required schema
does not have select rights to SYS.ALL_... views, and use a system user to log
with.

=item B<ScriptPrivileges.pl> B<-i> db1 B<-u> user B<-p> passwd B<-t> schema1.package1

Builds the creation scripts only for the packages 'schema1.package1' on database
instance db1.

=item B<ScriptPrivileges.pl> B<-i> db1 B<-u> user B<-p> passwd -l db2

Builds the creation scripts for all the packages in the DBLink's default schemas
of the remote database instance, which is accessed from this database instance
db1 via database link db2.

=item B<ScriptPrivileges.pl> B<-i> db1 B<-u> user B<-p> passwd B<-m> schema1,schema2 B<-l> db2

Builds the creation scripts for all the packages in the schemas 'schema1'
and 'schema2' on a remote database instance that is accessed from this
Oracle instance db1 via the database link db2.

=item B<ScriptPrivileges.pl> B<--help>

Provides detailed description.

=back

=head1 OPTIONS AND ARGUMENTS

B<ScriptPrivileges.pl> B<-u|--user> UserId B<-p|--password> Passwd [B<-i|--instance> Instance name]
[-l|--dblink DBLink] [-s|--schemas Schemas] [--contributors]
[-v|--version] [--quiet|--verbose|--debug] [-?|--help] [--man]

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

Schema name(s) for which the objects will be scripted out.
Either use -m schema1 -m schema2 or -m schema1,schema2.

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
    cpan> quit

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

B<5.> If you do want to run CPAN from Windows (you may need to if the above ppm-install
did not work), download the collection of Unix utilities for Windows from
www.hoekstra.co.uk/opensource, and put them somewhere in your path.

B<6.> You will also need a C/C++ compiler and a make utility.
Use cl.exe and nmake.exe from MS Visual Studio 6 or 7. Ensure that
C:\Program Files\Microsoft Visual Studio\VC98\bin is on your path,
(or wherever you have installed Visual Studio) so that nmake.exe and cl.exe
are visible. Note that this will not work with Visual Studio .Net 2002/2003!

B<7.> Change the following lines manually in  C:\Perl\lib\CPAN\Config.pm from:

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

=head1 ALTERNATIVES

You can try the following methods for very accurate results but without the
nice formatting:

=head2 Using Oracle9i++ DBMS_METADATA package:

From the SQLPLUS shell, type:

    SQL> connect <object_owner>
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

