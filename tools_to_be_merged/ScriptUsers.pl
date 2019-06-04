#!/usr/bin/perl
#----------------------------------------------------------------------------------#
#----------------------------------------------------------------------------------#
# FUNCTION:
# Scripts user creation script from an existing database into a installation file.
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
use Cwd;
use Oracle::Script::FileHeaders;
use Oracle::Script::Common;

#----------------------------------------------------------------------------------#
# Globals
my $file_name;                      # Script creation File name
my $sql;                            # SQL String
my @row;                            # Result set
my $dbh;                            # DB connection
my $mode=0;                         # DB Connection mode
my $year = ((localtime())[5]+1900); # Copyright Year
my $start_time=time();              # Start time
my $file_count=0;                   # File counter

# Command Line parameters
my ($instance,$userid,$password,$author,$verbose,$contributors,$version_display,$debug,$excel,$dblink,$quiet,$man,$help,$gnu);

#----------------------------------------------------------------------------------#
# Prints the version of this script and exits the program
sub version_display{
  print '$Header: $'."\n";
  exit(0);
}

#----------------------------------------------------------------------------------#
# Get list of users that match the selection list
sub get_user_list{
  my ($connection,$cursor,$users)=@_;
  my $sql=
      "select * ".
      "  from sys.all_users".(defined($dblink)?'\@'.$dblink:'').
      " where instr(upper(".$connection->quote($users)."),username) <> 0 ".
      " order by username";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting a list of users ".(defined($dblink)?'\@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get list of tablespaces that this user may use
sub get_logged_on_user_tablespaces{
  my ($connection,$cursor)=@_;
  my $sql="select * ".
          "  from sys.user_tablespaces".(defined($dblink)?'\@'.$dblink:'').
          " order by tablespace_name";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting a list of users ".(defined($dblink)?'\@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get list of tablespaces that this user may use
# Can only call this when the logged in as SYSDBA
sub get_user_tablespaces{
  my ($connection,$cursor,$user)=@_;
  my $sql="select * ".
          "  from sys.dba_ts_quotas".(defined($dblink)?'\@'.$dblink:'').
          " where username = ".$connection->quote($user).
          " order by tablespace_name";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting tablespaces for user $user ".(defined($dblink)?'\@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Main Program
GetOptions( 'instance|i=s'=>\$instance,
            'user|u=s'    =>\$userid,
            'password|p=s'=>\$password,
            'dblink|l=s'  =>\$dblink,
            'debug|d'     =>\$debug,
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
  $mode=ORA_SYSDBA;
}
if(!defined $password){
  warn "Database Password must be specified";
  pod2usage(-exitstatus=>1, -verbose=>0);
}

# Clean up parameters
$verbose=1 if($debug);

# Connect to the database
# Connect to the database
Oracle::Script::Common->info("Connecting to Database $instance...") if($verbose);
$dbh = DBI->connect("dbi:Oracle:$instance", $userid, $password, {ora_module_name=>$0, ora_session_mode=>$mode})
  || die "Unable to connect to $instance: $DBI::errstr\n";
Oracle::Script::Common->info("Connected.\n") if($verbose);

# We want dates to appear in nice text form
$dbh->do("ALTER SESSION SET NLS_DATE_FORMAT = 'YYYYMMDDHH24MISS'")
  || Oracle::Script::Common->warn("You have no access rights to ALTER SESSION SET NLS_DATE_FORMAT. Will use the current format.\n");

# Anticipate long values when dealing with Oracle data dictionary
$dbh->{LongReadLen} = 512 * 1024;
$dbh->{LongTruncOk} = 1;

if(defined($dblink)){
  $dblink=Oracle::Script::Common->get_dblink_full_name($dbh,$dblink);
}

$file_name="users.sql";
Oracle::Script::Common->info("Building users creation script for database $instance".(defined($dblink)?'@'.$dblink:'')." in file $file_name\n") if(!$quiet);
open(F,"+>".$file_name) || die "Could not open file $file_name for writing. $!\n";
print F Oracle::Script::FileHeaders->MakeSQLFileHeader($file_name,$userid,$author,$dblink);
print F "-- Creation script for users\n--\n";
print F Oracle::Script::FileHeaders->OracleDBDetails($userid,$password,$instance);
print F "-- To run this script from the command line:\n";
print F "-- sqlplus \"$userid/[password]\@[instance]  as sysdba\" \@$file_name\n";
print F "------------------------------------------------------------------------------\n";
print F "set feedback off;\n";
print F "henever SQLERROR exit failure\n";
print F "set serveroutput on size 1000000\n";
print F "set pagesize 0\n";
print F "set verify off\n";
print F "spool log/%ORACLE_SID%_users.log\n";
print F "prompt Creating users\n";
print F "\n";

# Get the specified users that do actually exist

print F "/\n";
print F "------------------------------------------------------------------------------\n";
print F "-- Create users\n";
print F "------------------------------------------------------------------------------\n";
print F "\n";

# Script users


    print F "-- Drop user if already exists:\n";
    print F "declare \n";
    print F "  v_count integer;\n";
    print F "begin\n";
    print F "  select count(*)\n";
    print F "    into v_count\n";
    print F "    from sys.dba_users\n";
    print F "   where username = '''||c.username||''';\n";
    print F "  if(v_count>0) then\n";
    print F "    execute immediate ''drop user '||c.username||' cascade'';\n";
    print F "  end if;\n";
    print F "end;\n";
    print F "/\n";
    print F " \n";

    print F "-- Create user:\n";
    print F "create user '||c.username\n";
    print F "  identified by '||c.username||'ADM'\n";
    print F "  default tablespace '||c.default_tablespace\n";
    print F "  temporary tablespace '||c.temporary_tablespace\n";
    print F "  profile '||c.profile\n";
    -- Add tablespaces
    for c_t in c_tablespaces(c.username) loop
      print F "  quota unlimited on '||c_t.tablespace_name\n";
    end loop;
    print F ";\n";
    print F " \n";

  print F "spool off\n";



print F Oracle::Script::FileHeaders->MakeSQLFileFooter();
close F;

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

ScriptUsers.pl - Scripts user creation script from an existing database into a installation file.

=head1 SYNOPSIS

=over 4

=item B<ScriptUsers.pl> B<-i> db1 B<-u> sys_user B<-p> passswd

Builds the user creation scripts of the database instance db1.

=item B<ScriptUsers.pl> B<-i> db1 B<-u> sys_user B<-p> passswd  B<-x>

Creates a spreadsheet describing the user on database instance db1.

=item B<ScriptUsers.pl> B<--help>

Provides detailed description.

=back

=head1 OPTIONS

B<ScriptUsers.pl> B<-i|--instance> DB B<-u|--user> System UserId B<-p|--password> Passwd [-l|--dblink DBLink]
[-x|--spreadsheet] [--contributors] [-v|--version] [--author author name] [--gnu] [--quiet|--verbose|--debug] [-?|--help] [--man]

=head2 Mandatory

=over 4

=item B<-i|--instance Oracle Database instance name>

Specify the TNS name of the Oracle Database instance, unless the environment variable ORACLE_SID is set to the desired instance.

=item B<-u|--user User login Id>

System User / schema login Id. This is usually 'sys' or 'system'. If it is not specified, it defaults to 'sys'.

=item B<-p|--password Password>

Password to accompany the system login Id

=back

=head2 Optional

=over 4

=item B<-l|--dblink Database link>

Database link Id to a remote database. If the required schema on the
remote database does not have select rights to its SYS.ALL_... views,
get your DBA to grant remote DBlink user select access to these views.
It is helpful to specify the fully-qualified link name (e.g. DBLINK.DOMAIN).
If no domain is specified, the default WORLD domain will be assumed.

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

A file with a .sql file extension will be created, which will contain a file
header and a file footer.

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

B<1.> Configure depth level of data scripting.

B<2.> Check if database already exists in target service.

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

