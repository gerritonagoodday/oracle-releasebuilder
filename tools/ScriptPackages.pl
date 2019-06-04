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
use Oracle::Script::FileHeaders;
use Oracle::Script::Common;


#----------------------------------------------------------------------------------#
# Globals
# Command Line parameters
my ($instance,$meta_schemas,@meta_schemas,$meta_objects,@objects,$userid,$password,$author,$verbose,$contributors,$version_display,$debug,$excel,$dblink,$quiet,$man,$help,$gnu,$grants,$no_storage);
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
  print '$Header: ScriptPackages.pl 1.2 2005/03/03 11:49:19GMT ghoekstra PRODUCTION  $'."\n";
  exit(0);
}

#----------------------------------------------------------------------------------#
# Get database link details
# This can sometimes return more than one record for the given dblink name, as the
# DBLINK may be represented in terms of all the SQL*Net configurations in use in
# the enterprise by eager DBA's: eg. DBLINK.WORLD and DBLINK.DOMAIN.
# When more than one record is returned, use the database domain name to select
# the most appropriate one. When the domain name can not be found, then
# the default domain name is will be deemed to be WORLD (and the other links are legacy?)
sub get_dblink_details{
  my ($connection,$cursor,$owner,$db_link)=@_;
  my $sql=
      "select * ".
      "  from sys.all_db_links ".
      " where db_link like upper(".$connection->quote($db_link).")||'%' ".
      "   and owner=upper(".$connection->quote($owner).") ";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting details for Database Link $dblink.\n".
    "Please log in directly to the database that you want to build scripts for.\n".
    $cursor->errstr()."\n";
  # If we have more than one record describing the database link, then get the domain name
  if($cursor.count()>2){
    $sql="select sys_config(".$connection->quote('user_env').",".
         $connection->quote('domain').") \n".
         "from dual";
    $cursor=$connection->prepare($sql);
    $cursor->execute() || warn "Could not get domain name\n";
  }
  #etc...
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get all Package names belong to the list of schemas
sub get_scriptable_packages{
  my ($connection,$cursor,$owners)=@_;
  my $sql=qq{
    select distinct o.owner, o.object_name, o.object_type
      from sys.all_objects o
     where (o.object_type = 'PACKAGE' or o.object_type = 'PACKAGE BODY')
       and instr(upper('$owners'),o.owner) <> 0
     order by 1,2,3
  };
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting packages in schemas $owners".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get all Package names that we want to script out
sub get_package_details{
  my ($connection,$cursor,$owner,$package,$type)=@_;
  my $sql=qq{
    select s.text
      from all_source s
     where s.name = upper('$package')
       and s.owner= upper('$owner')
       and s.type = upper('$type')
     order by line
  };
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting details of package $type $owner.$package".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Checks if package exists
sub does_package_exist{
  my ($connection,$cursor,$owner,$package)=@_;
  my $sql=qq{
    select distinct o.owner, o.object_name, o.object_type
      from sys.dba_objects o
     where (o.object_type = 'PACKAGE' or o.object_type = 'PACKAGE BODY')
       and upper('$owner')  = o.owner
       and upper('$package')= o.object_name
     order by 1,2,3
  };
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error checking if package $owner.$package exists.\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get Grantees
# TODO
#sub get_grantees{
#  my ($connection,$cursor,$owner,$table)=@_;
#  my $sql=
#    "select GRANTEE ".
#    "     , count(*) as grant_count ".
#    "  from sys.all_tab_privs".(defined($dblink)?'@'.$dblink:'').
#    " where table_schema = ".$connection->quote($owner).
#    "   and table_name = ".$connection->quote($table).
#    " group by GRANTEE ".
#    " order by 1";
#  $cursor=$connection->prepare($sql);
#  $cursor->execute() || die "Error getting table grantees for table $owner.$table".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
#  return $cursor;
#}

#----------------------------------------------------------------------------------#
# Get Grants
# TODO
#sub get_grants{
#  my ($connection,$cursor,$owner,$table,$grantee)=@_;
#  my $sql=
#    "select * ".
#    "  from sys.all_tab_privs".(defined($dblink)?'@'.$dblink:'').
#    " where grantee = ".$connection->quote($grantee).
#    "   and table_schema = ".$connection->quote($owner).
#    "   and table_name = ".$connection->quote($table).
#    " order by privilege";
#  print $sql."\n" if $verbose;
#  $cursor=$connection->prepare($sql);
#  $cursor->execute() || die "Error getting table grants for table $owner.$table".(defined($dblink)?'@'.$dblink:'')." grantee $grantee.\n".$cursor->errstr()."\n";
#  return $cursor;
#}

#----------------------------------------------------------------------------------#
# Script to text file
sub ScriptTextFile{
  # We now have a list of all the tables which to create CREATION scripts for:
  foreach (@schema_objects){
    my $owner =$_->{"schema"};
    my $object=$_->{"object"};
    my $type  =$_->{"type"};

    # Make up file name
    my $short_file_name=lc($object).($type eq 'PACKAGE BODY'?".plb":".plh");
    my $file_name = lc($owner).".packages.$short_file_name";
    Oracle::Script::Common->info("Building creation script for package ".($type eq 'PACKAGE BODY'?"body":"header")." $owner.$object".(defined($dblink)?'@'.$dblink:'')." in file $short_file_name\n") if !$quiet;
    open(F,"+>".$file_name) || die "Could not open temporary file $file_name for writing. $!\n";
    $file_count++;
    my $lines=0;
    my $create_done=0;
    my $c_source;

    $c_source=get_package_details($dbh,$c_source,$owner,$object,$type);
    my $source_row_ref;

    while($source_row_ref=$c_source->fetchrow_hashref()){
      # Reconstruct the fully-qualified package name so that the resultin gscript can be run
      # by another (sys) schema.
      if($create_done==0){
        # Look for package name in source code and add schema name
        # Must not be in a commented section.
        #   This is a crude and incomplete check - should parse for / * ... * / style comments as well
        if(!($source_row_ref->{TEXT}=~/^ *--/)){
          if($source_row_ref->{TEXT}=~s/$object/$owner\.$object/){
            # Found package name - remove padding spaces
            $source_row_ref->{TEXT}=~s/ +/ /g;
            $create_done=1;
          }
        }
      }

      if($lines==0){
        # First line always contains 'package'/'package body' or 'package <spaces><name>'/'package body <spaces><name>'
        # The package name is wherever it was left in the original code but with the schema name replaced with spaces (why?).
        # Turn this into 'create or replace package/package body':
        print F "create or replace $source_row_ref->{TEXT}";
      }else{
        print F "$source_row_ref->{TEXT}";
      }
      $lines++;
    }
    # Add a forward slash to make it compile when it has been installed.
    print F "/\n";

    # Only include them if explicitly required - there is another script that will manage all privileges
    if($grants){
      undef;
    }

    # Finish File
    close F;

    if($debug){
      # Display file to stdout
      open(F,"<".$file_name)||die "Could not open $file_name for display. $!\n";
      my @lines=<F>;
      close F;
      foreach(@lines){Oracle::Script::Common->debug("$_");}
    }
    Oracle::Script::Common->debug("Package ".($type eq 'PACKAGE BODY'?"body":"header")." $owner.$object has $lines lines.\n") if $debug;

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
$dbh->do("ALTER SESSION SET NLS_DATE_FORMAT = 'YYYYMMDDHH24MISS'")
  || Oracle::Script::Common->warn("You have no access rights to ALTER SESSION SET NLS_DATE_FORMAT. Will use the current format.\n");

# Anticipate long values when dealing with Oracle data dictionary
$dbh->{LongReadLen} = 512 * 1024;
$dbh->{LongTruncOk} = 1;

if(defined($dblink)){
  $dblink=Oracle::Script::Common->get_dblink_full_name($dbh,$dblink);
}

# -o parameter:
# Get all individually specified objects
if($meta_objects){
  my @spec_objects=split(/,/,$meta_objects);
  foreach my $object(@spec_objects){
    my @schema_object=split(/\./,$object);
    # Where no schema name is defined, default to the user login schema
    if(!exists $schema_objects[1]){
      push(@schema_object,@schema_object[0]);
      @schema_object[0]=$userid;
    }
    print "Individually specified package: ",uc(@schema_object[0].@schema_object[1]),"\n" if($verbose);
    # Check if this object exists
    my $cursor;
    $cursor=does_package_exist($dbh,$cursor,@schema_object[0],@schema_object[1]);
    # Fetch single record
    @row=$cursor->fetchrow_array();
    if(scalar(@row)==0){
      die "Individually specified package ",uc(@schema_object[0].@schema_object[1])," does not exist or should not scripted.\n";
    }else{
      push(@schema_objects,{"schema"=>uc(@schema_object[0]),"object"=>uc(@schema_object[1])});
    }
    $cursor->finish();
  }
}

# -s parameter:
# Get all schemas for which object create scripts will be created, if any schemas are defined at all
# You may have specified other schemas, but either they don't exist or they don't have any objects in them
if($meta_schemas){
  # Get all the objects that belong to the schemas
  my $cursor;
  $cursor=get_scriptable_packages($dbh,$cursor,$meta_schemas);
  my $objects_ref = $cursor->fetchall_arrayref();
  foreach my $row(@{$objects_ref}){
    my ($schema,$object,$type) = @{$row};
    print "Package ".lc($type)." specified by schema: $schema.$object\n" if($verbose);
    push(@schema_objects,{"schema"=>$schema,"object"=>$object,"type"=>$type});
  }
  $cursor->finish();
}

# Default, if no schemas or objects have been defined
if(!$meta_objects && !$meta_schemas){
  print "Extracting scripts for all packages in schema $userid\n" if($verbose);
  # Get all the objects that belong to the schemas
  my $cursor;
  $cursor=get_scriptable_packages($dbh,$cursor,$userid);
  my $objects_ref = $cursor->fetchall_arrayref();
  foreach my $row(@{$objects_ref}){
    my ($schema,$object,$type) = @{$row};
    print "Package ".lc($type)." specified by schema: $schema.$object\n" if($verbose);
    push(@schema_objects,{"schema"=>$schema,"object"=>$object,"type"=>$type});
  }
  $cursor->finish();
}

# Remove duplicate items from @schema_objects
my $last;
my @schema_objects_;
foreach (sort {
                $a->{"schema"}.".".$a->{"object"}.".".$a->{"type"} <=>
                $b->{"schema"}.".".$b->{"object"}.".".$a->{"type"}
              } @schema_objects){
  if($last ne $_->{"schema"}.".".$_->{"object"}.".".$_->{"type"}){
    push(@schema_objects_,{"schema"=>$_->{"schema"},"object"=>$_->{"object"},"type"=>$_->{"type"}});
  }
  $last=$_->{"schema"}.".".$_->{"object"}.".".$_->{"type"};
}
@schema_objects=@schema_objects_;

ScriptTextFile;

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

ScriptPackages.pl - Generates formal Package creation scripts

=head1 SYNOPSIS

=over 4

=item B<ScriptPackages.pl> B<-i> db1 B<-u> user B<-p> passwd

Builds the creation scripts for all the packages in the schema 'user' on
database instance db1.

=item B<ScriptPackages.pl> B<-i> db1 B<-u> user B<-p> passswd B<-m> schema1 B<-m> schema2

Builds the creation scripts only for all the packages in the schemas 'schema1'
and 'schema2' on database instance db1. Use this form if the required schema
does not have select rights to SYS.ALL_... views, and use a system user to log
with.

=item B<ScriptPackages.pl> B<-i> db1 B<-u> user B<-p> passwd B<-t> schema1.package1

Builds the creation scripts only for the packages 'schema1.package1' on database
instance db1.

=item B<ScriptPackages.pl> B<-i> db1 B<-u> user B<-p> passwd -l db2

Builds the creation scripts for all the packages in the DBLink's default schemas
of the remote database instance, which is accessed from this database instance
db1 via database link db2.

=item B<ScriptPackages.pl> B<-i> db1 B<-u> user B<-p> passwd B<-m> schema1,schema2 B<-l> db2

Builds the creation scripts for all the packages in the schemas 'schema1'
and 'schema2' on a remote database instance that is accessed from this
Oracle instance db1 via the database link db2.

=item B<ScriptPackages.pl> B<--help>

Provides detailed description.

=back

=head1 OPTIONS AND ARGUMENTS

B<ScriptPackages.pl> B<-u|--user> UserId B<-p|--password> Passwd [B<-i|--instance> Instance name]
[-l|--dblink DBLink] [-s|--schemas Schemas] [-o|--objects Packages]
[-g|--grants] [--contributors] [-v|--version] [--quiet|--verbose|--debug] [-?|--help] [--man]

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

=item B<-o|--objects List of package names>

Object(s) belonging to the logged in schema or the DB Link's default schema.
You may specify a different schema name using the [schema].[object] notation.
Either use -o object1 -o object2 or -t object1,object2.

=item B<-g|--grants Script grants>

By default grant scripts are not included since there is another script that
will centrally create these. Set this flag if you explicitly require them in
this script.

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

