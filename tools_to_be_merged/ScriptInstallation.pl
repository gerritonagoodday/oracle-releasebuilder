#!/usr/bin/perl
#----------------------------------------------------------------------------------#
#----------------------------------------------------------------------------------#
# FUNCTION:
# Scripts the database for a set of schema names into nice installation files.
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
use File::Basename;
use Oracle::Script::FileHeaders;
use Oracle::Script::Common;
use Cwd;


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

# Types of objects that we want to script
# These are put in the best possible order to minimise compilation errors whilst
# running the resulting installation.

my %script_objects=(
  database             =>{proc=>"ScriptDatabase",
                          enabled=>0,
                          desc=>"a brand new database",
                          type=>"central",
                          order=>10},
  tablespaces          =>{proc=>"ScriptTables",
                          enabled=>0,
                          desc=>"new tablespaces",
                          type=>"central",
                          order=>20},
  roles                =>{proc=>"ScriptRoles",
                          enabled=>1,
                          desc=>"roles",
                          type=>"central",
                          order=>30},
  users                =>{proc=>"ScriptUsers",
                          enabled=>1,
                          desc=>"schemas / users",
                          type=>"central",
                          order=>40},
  directories          =>{proc=>"ScriptDirectories",
                          enabled=>0,
                          desc=>"directory objects that map to real directories on the server",
                          type=>"central",
                          order=>50},
  databaselinks        =>{proc=>"ScriptDatabaseLinks",
                          enabled=>0,
                          desc=>"links to remote databases",
                          type=>"central",
                          order=>60},
  sequences            =>{proc=>"ScriptSequences",
                          enabled=>1,
                          desc=>"sequences",
                          type=>"per-schema",
                          order=>70},
  tables               =>{proc=>"ScriptTables",
                          enabled=>1,
                          desc=>"tables",
                          type=>"per-schema",
                          order=>80},
  views                =>{proc=>"ScriptViews",
                          enabled=>1,
                          desc=>"views",
                          type=>"per-schema",
                          order=>90},
  types                =>{proc=>"ScriptTypes",
                          enabled=>1,
                          desc=>"types",
                          type=>"per-schema",
                          order=>95},
  exceptions           =>{proc=>"ScriptExceptions",
                          enabled=>0,
                          desc=>"exceptions",
                          type=>"per-schema",
                          order=>100},
  functions            =>{proc=>"ScriptFunctions",
                          enabled=>0,
                          desc=>"PL/SQL functions",
                          type=>"per-schema",
                          order=>110},
  procedures           =>{proc=>"ScriptProcedures",
                          enabled=>0,
                          desc=>"PL/SQL procedures",
                          type=>"per-schema",
                          order=>120},
  packages             =>{proc=>"ScriptPackages",
                          enabled=>1,
                          desc=>"PL/SQL packages",
                          type=>"per-schema",
                          order=>130},
  triggers             =>{proc=>"ScriptTriggers",
                          enabled=>1,
                          desc=>"triggers",
                          type=>"per-schema",
                          order=>140},
  libraries            =>{proc=>"ScriptLibraries",
                          enabled=>0,
                          desc=>"library objects",
                          type=>"per-schema",
                          order=>150},
  extprocs             =>{proc=>"ScriptExtProcs",
                          enabled=>0,
                          desc=>"external procedures written in C",
                          type=>"central",
                          type=>"per-schema",
                          order=>160},
  privileges           =>{proc=>"ScriptPrivileges",
                          enabled=>1,
                          desc=>"privileges to all scripted objects",
                          type=>"central",
                          order=>170},
  data                 =>{proc=>"ScriptData",
                          enabled=>1,
                          desc=>"table data population scripts",
                          type=>"specific",
                          order=>180,commands=>""},
);

my %affected_schemas=();

# Command Line parameters
my ($instance,$schemas,@schemas,@objects,$meta_objects,@meta_schemas,$meta_schemas,@schema_objects,$userid,$password,$author,$verbose,$contributors,$version_display,$debug,$excel,$dblink,$quiet,$man,$help,$gnu,$ignore_empty,$no_storage,$company_name);

# Create scripting tree
my $cmd;
my $cwd=getcwd();
my $application_dir="application";
my $application_path="$cwd/$application_dir";
eval{rmtree($application_path);};
mkdir($application_path) if(!-d $application_path);
my $install_dir="install";
my $install_path="$cwd/$install_dir";
eval{rmtree($install_path);};
mkdir($install_path) if(!-d $install_path);

#----------------------------------------------------------------------------------#
# Prints the version of this script and exits the program
sub version_display{
  print '$Header: $'."\n";
  exit(0);
}

#----------------------------------------------------------------------------------#
# Prints the contributors and then exits.
sub contributors {
print <<EOF;
Author: Gerrit Hoekstra <gerrit\@hoekstra.co.uk>
        www.hoekstra.co.uk
No other contributors so far.
EOF
  exit(0);
}

#----------------------------------------------------------------------------------#
# Make up a type-specific installation script in the install directory
# Assumption: CWD is the directory that this program is run from
sub make_objecttype_script {
  my $object=shift;

  open (F,"+>$install_path/$object.ksh");
  print F Oracle::Script::FileHeaders->MakeSHFileHeader($company_name);
  print F Oracle::Script::FileHeaders->OracleDBDetails($userid, $password,$instance,'#');
  print F "# $object installation script. To run this script:\n";
  print F "#   ./$object.ksh userid password database\n";
  print F "#------------------------------------------------------------------------------\n";
  print F "\n";
  # index all the files that were created
  foreach my $path (<$application_path/*>){
    if(-d $path){
      my $schema=basename($path);
      $affected_schemas{$schema}++; # To be sure
      # Only do directories
      foreach my $file_path (<$application_path/$schema/$object/*.sql>){
        my $line="sqlplus \$1/\$2\@\$3 @../$application_dir/$schema/$object/".basename($file_path)."\n";
        push (@{$script_objects{$object}{commands}},$line);
        print F "$line";
      }
    }
  }
  print F Oracle::Script::FileHeaders->MakeSHFileFooter;
  close F;
}


#----------------------------------------------------------------------------------#
# Main Program

# Save command line
my $cmd_line="$0 ".join(' ',@ARGV);

GetOptions( 'instance|i=s'=>\$instance,
            'user|u=s'    =>\$userid,
            'password|p=s'=>\$password,
            'dblink|l=s'  =>\$dblink,
            'schemas|s=s' =>\@meta_schemas,
            'objects|o=s' =>\@objects,
            'debug|d'     =>\$debug,
            'no-storage'  =>\$no_storage,
            'ignoreempty' =>\$ignore_empty,
            'author=s'    =>\$author,
            'contributors'=>\$contributors,
            'version|v'   =>\$version_display,
            'verbose'     =>\$verbose,
            'company_name'=>\$company_name,
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

# -s parameter:
# Get all schemas for which object create scripts will be created, if any schemas are defined at all
# You may have specified other schemas, but either they don't exist or they don't have any objects in them
foreach my $schema (@meta_schemas){
  Oracle::Script::Common->debug("Schema ".lc($schema)."\n");
  push(@schema_objects,{"owner"=>lc($schema)});
}

# Default, if no schemas or objects have been defined
if(!$meta_objects && !$meta_schemas){
  Oracle::Script::Common->debug("Schema ".lc($userid)."\n") if $debug;
  push(@schema_objects,{"owner"=>lc($userid)});
}

# Remove duplicate schemas
my $last;
my @schema_objects_;
foreach (sort {$a->{"owner"}<=>$b->{"owner"}} @schema_objects){
  if($last ne $_->{"owner"}){
    push(@schema_objects_,{"owner"=>$_->{"owner"}});
  }
  $last=$_->{"owner"};
}
@schema_objects=@schema_objects_;

# Flatten out for passing to scripts
my @owners;
foreach (@schema_objects){
  push @owners, $_->{"owner"};
}
my $schemas=join(',',@owners);

Oracle::Script::Common->info("Central scripts\n") if $verbose;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
foreach my $object (sort {
                      $script_objects{$a}{order}<=>$script_objects{$b}{order}
                    } keys %script_objects){
  if($script_objects{$object}{type} eq "central"){
    if($script_objects{$object}{enabled}){
      chdir($install_path);
      Oracle::Script::Common->debug("$object: $script_objects{$object}{proc},$script_objects{$object}{desc},$script_objects{$object}{type}\n") if $debug;
      $cmd="perl $cwd/$script_objects{$object}{proc}.pl -i $instance -u $userid -p $password -s $schemas";
      if(defined $company_name){$cmd.=" -c $company_name";}
      if(defined $debug){$cmd.=" -d";}elsif(defined $verbose){$cmd.=" -v";}
      Oracle::Script::Common->info("Creating $script_objects{$object}{desc}...\n") if $debug;
      eval{
        Oracle::Script::Common->debug("$cmd\n") if $debug;
        system($cmd);
        push @{$script_objects{$object}{commands}},"sqlplus \$1/\$2\@\$3 \@$object.sql\n";
      };
      chdir($cwd);
    }
  }
};

Oracle::Script::Common->info("Schema-based Object scripts\n") if $verbose;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
foreach my $object (sort {
                      $script_objects{$a}{order}<=>$script_objects{$b}{order}
                    } keys %script_objects){
  if($script_objects{$object}{type} eq "per-schema"){
    if($script_objects{$object}{enabled}){
      chdir($application_path);
      Oracle::Script::Common->debug("$object: $script_objects{$object}{proc},$script_objects{$object}{desc},$script_objects{$object}{type}\n") if $debug;
      $cmd="perl $cwd/$script_objects{$object}{proc}.pl -i $instance -u $userid -p $password -s $schemas";
      if(defined $company_name){$cmd.=" -c $company_name";}
      if(defined $debug){$cmd.=" -d";}elsif(defined $verbose){$cmd.=" -v";}
      Oracle::Script::Common->info("Creating $script_objects{$object}{desc}...\n") if $debug;
      eval{
        Oracle::Script::Common->debug("$cmd\n") if $debug;
        system($cmd);
      };
      chdir($cwd);
      # Make up a type-specific installation script
      make_objecttype_script($object);
    }
  }
};

Oracle::Script::Common->info("Specific object scripts\n") if $verbose;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
if((scalar @objects) > 0){   # If any tables for population have been defined
  # Only if it is enabled
  if($script_objects{data}{enabled}){
    chdir($application_path);
    $cmd="perl $cwd/$script_objects{data}{proc}.pl -i $instance -u $userid -p $password -o ".join(',',@objects);
    if(defined $company_name){$cmd.=" -c $company_name";}
    if(defined $debug){$cmd.=" -d";}elsif(defined $verbose){$cmd.=" -v";}
    eval{
      debug("$cmd\n");
      system($cmd);
    };
    chdir($cwd);

    # Make up a type-specific installation script
    make_objecttype_script('data');
  }
}

Oracle::Script::Common->info("Create schema-based installation file\n") if $verbose;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
foreach my $schema (keys %affected_schemas){
  open (  SCHEMA,"+>$install_path/".$schema."_install.ksh");
  print   SCHEMA Oracle::Script::FileHeaders->MakeSHFileHeader($company_name);
  print   SCHEMA Oracle::Script::FileHeaders->OracleDBDetails($userid, $password,$instance,'#');
  print   SCHEMA "# Schema-based installation script for schema $schema.\n";
  print   SCHEMA "# To run this script:\n";
  print   SCHEMA "# ./".$schema."_install.ksh userid password database\n";
  print   SCHEMA "#------------------------------------------------------------------------------\n";
  print   SCHEMA "\n";
  foreach my $object (sort {
                        $script_objects{$a}{order}<=>$script_objects{$b}{order}
                      } keys %script_objects){
    if($script_objects{$object}{enabled}){
      if($script_objects{$object}{commands} && scalar @{$script_objects{$object}{commands}} > 0){
        print SCHEMA "echo Creating $script_objects{$object}{desc}\n";
        if($script_objects{$object}{commands}){
          foreach (@{$script_objects{$object}{commands}}){
            if(/\/$schema\/.+\.sql/){
              print SCHEMA "$_";
            }
          }
        }
        print SCHEMA "\n";
      }
    }
  }
  print   SCHEMA Oracle::Script::FileHeaders->MakeSHFileFooter;
  close   SCHEMA;
}

Oracle::Script::Common->info("Create core installation file\n") if $verbose;
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
open (  CORE,"+>$install_path/install.ksh");
print   CORE Oracle::Script::FileHeaders->MakeSHFileHeader($company_name);
print   CORE Oracle::Script::FileHeaders->OracleDBDetails($userid, $password,$instance,'#');
print   CORE "# Database Installation script \n";
print   CORE "#\n";
print   CORE "# This installation was generated using the Oracle::Script package with the command:\n";
print   CORE "#   $cmd_line\n";
print   CORE "#\n";
print   CORE "# To run this script:\n";
print   CORE "# ./install.ksh userid password database\n";
print   CORE "#------------------------------------------------------------------------------\n";
print   CORE "\n";
foreach my $object (sort {
                      $script_objects{$a}{order}<=>$script_objects{$b}{order}
                    } keys %script_objects){
  if($script_objects{$object}{enabled}){
    if($script_objects{$object}{commands} && scalar @{$script_objects{$object}{commands}} > 0){
      print CORE "echo Creating $script_objects{$object}{desc}\n";
      if($script_objects{$object}{commands}){
        foreach (@{$script_objects{$object}{commands}}){
          print CORE "$_";
        }
      }
      print CORE "\n";
    }
  }
}

print   CORE "echo Compiling the application\n";
print   CORE "sqlplus \$1/\$2\@\$3 <<!\n";
print   CORE "set feedback off verify off\n";
print   CORE "spool log/%ORACLE_SID%_compile.log\n";
foreach (keys %affected_schemas){
  print CORE "prompt Compiling schema $_:\n";
  print CORE "exec dbms_utility.compile_schema('$_');\n";

}
print   CORE "\n";
print   CORE "prompt The following database objects did not compile:\n";
print   CORE "select object_type||': '||owner||'.'||object_name as \"Invalid Objects\"\n";
print   CORE "  from sys.all_objects\n";
print   CORE " where trim(object_type) in ('PACKAGE','PACKAGE BODY','PROCEDURE','FUNCTION')\n";
print   CORE "   and status = 'INVALID'\n";
print   CORE " order by object_type,owner,object_name;\n";
print   CORE "spool off\n";
print   CORE "!\n";
print   CORE "echo \"Application Installation complete.\"\n";
print   CORE "echo \"Refer to the log files in the ./log directory for further details\".\n";
print   CORE "\n";
print   CORE Oracle::Script::FileHeaders->MakeSHFileFooter;
close   CORE;

# Make KSH scripts executable
foreach(<$install_path/*.ksh>){ chmod(0777,$_);}


END:{
# Disconnect
  if(defined $dbh){
    Oracle::Script::Common->info("Disconnecting...") if($verbose);
    $dbh->disconnect() || Oracle::Script::Common->warn("Failed to disconnect from $instance. ".$dbh->errstr()."\n");
    Oracle::Script::Common->info("done.\n") if($verbose);
  }
  my $proc_time=time()-$start_time;
  Oracle::Script::Common->info("Created application installation in $proc_time seconds.\n") if(!$quiet);
  exit(0);
}



__END__

=head1 NAME

ScriptInstallation.pl - Scripts the database for a set of schema names into installation files

=head1 SYNOPSIS

=over 4

=item B<ScriptInstallation.pl> B<-i> db1 B<-u> user B<-p> passswd B<-s> schema1,schema2

Builds the creation scripts only for all objects in the schemas 'schema1'
and 'schema2' on database instance db1.

=item B<ScriptInstallation.pl> B<-i> db1 B<-u> user B<-p> passwd B<-s> schema1,schema2 B<-l> db2

Builds the creation scripts for all the objects in the schemas 'schema1'
and 'schema2' on a remote database instance that is accessed from this
Oracle instance db1 via the database link db2.

=item B<ScriptInstallation.pl> B<-i> db1 B<-u> user B<-p> passswd B<-s> schema1,schema2 B<-x>

Creates a spreadsheet describing all objects in the schemas 'schema1'
and 'schema2' on database instance db1.

=item B<ScriptInstallation.pl> B<--help>

Provides detailed description.

=back

=head1 OPTIONS

B<ScriptInstallation.pl> B<-i|--instance> DB B<-u|--user> UserId B<-p|--password> Passwd [-l|--dblink DBLink]
[-s|--schemas Schemas] [-x|--spreadsheet] [--contributors] [-t|--tables Tables]
[-v|--version] [--author author name] [--gnu] [--quiet|--verbose|--debug] [-?|--help] [--man]

=head2 Mandatory

=over 4

=item B<-i|--instance Oracle Database instance name>

Specify the TNS name of the Oracle Database instance, unless the environment variable ORACLE_SID is set to the desired instance.

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

=item B<-o|--objects List of Tables>

List of tables for which data population scripts need to be created.
If this is not specified, then no data population scripts are created.
Either use the form B<-o object1 -o object2> or the form B<-o object1,object2>.

=item B<-g|--grants Script grants>

By default grant scripts are not included since there is a central script that
will create these. Set this flag if you explicitly require them in separate scripts.

=item B<--no_storage>

Do not specify any table storage parameters. Storage parameters are included by default
and are substitued with values appropriate to the target database during installation time.

=item B<--ignoreempty>

Ignore empty data tables - used with option B<-o>

=item B<-x|--spreadsheet>

Create a Spreadsheet report of the objects

=item B<--author Name of Author/Company>

The name of the database author or company to be used for an optional
copyright notice. With this option used, a commercial or the GNU license
(if you specify the --gnu option) will be included in the header of
every generated file.

=item B<--gnu>

The GNU license will be included in the header of every generated file,
asserting copyright and copyleft to the specified author (if you specified the --author option).

=item B<--contributors>

List of contributors.

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

This program scripts an Oracle database for a given set of schema names into nice installation files.
It avoids the use of complex and proprietory tools, installs easily on most operating systems
that support Perl, and occupies a small footprint. It has been tested with Oracle version 8, 9 and 10 databases.

This program creates output files in a directory tree shown below that is
based off the current directory (probably the directory that you are running
this script from).
Output files are arranged in the form C<schema_name/object_type/object_name.sql>,
where the object types are tables, data, sequences, packages, functions,
procedures, exceptions, external procedures, views, types and triggers.
All directory and file names are in lower case. Any existing files in the tree
will be overwritten.

    [Current Directory]-+-application-+-[schema1]-+-data
                        |             |           |
                        |             |           +-exceptions
                        |             |           |
                        |             |           +-extprocs
                        |             |           |
                        |             |           +-functions
                        |             |           |
                        |             |           +-packages
                        |             |           |
                        |             |           +-procedures
                        |             |           |
                        |             |           +-sequences
                        |             |           |
                        |             |           +-tables
                        |             |           |
                        |             |           +-triggers
                        |             |           |
                        |             |           +-views
                        |             |           |
                        |             |           +-types
                        |             |
                        |             +-[schema2]-+....
                        |
                        +-install

You can run each resulting scripts individually using SQLPLUS
to create the desired object on an Oracle instance.
The script contains instructions on how it should be run. It goes along this line:

    # sqlplus "sys/[password]@[instance] as sysdba" @[script]

An installation script is created in the 'install' directory for each object
type that calls the smaller scripts which creates each object.
The object-type installation scripts are run on in a similar way, e.g.

    # sqlplus "sys/[password]@[instance] as sysdba" @tables

A schema-oriented installation script is also created for each application schema
that calls the object creation scripts that belong to the particular schema.
Again, the installation scripts are run on in a similar way, e.g.

    # sqlplus "sys/[password]@[instance] as sysdba" @schema_dwh

All the object-type scripts are called from an overall installation script.

    # ./install.ksh

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

