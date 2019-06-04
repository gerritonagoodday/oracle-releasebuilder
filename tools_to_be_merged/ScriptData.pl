#!/usr/bin/perl
#----------------------------------------------------------------------------------#
#----------------------------------------------------------------------------------#
# FUNCTION:
# Creates table population scripts from the contents of existing tables or views
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
# TODO: Deal in a nice way with tables that use a sequence-based keys
#       Deal with column types BLOB's, CLOB's, LOB's, RAW's, XML types, BFILE's, ROWID's, XML
#       Deal with ownership of directory creation on Unix
#       Allow for Column-width based CSV files
#       Turn this into a CPAN component.
#       Command-line interfaces needs some fixing - get configed between logged in
#       schema and specified schemas
#----------------------------------------------------------------------------------#

use strict;
use DBI;
use DBD::Oracle qw(:ora_session_modes);
use Getopt::Long;
use File::Copy;
use Oracle::Script::FileHeaders;
use Oracle::Script::Common;
use Pod::Usage;

#----------------------------------------------------------------------------------#
# Globals
my ($instance,$meta_schemas,$meta_tables,$userid,$password,$company_name,$verbose,$contributors,$version_display,$debug,$excel,$dblink,$csv,$csvheader,$csvseparator,$csvlinefeed,$author,$gnu,$quiet,$help,$man);
my $sql;                            # SQL String
my @row;                            # Result set
my $dbh;                            # DB connection
my $mode=0;                         # DB Connection mode
my @schema_tables;                  # Schema Table list
my @objects;
my @meta_schemas;
my $cmd;
my $table_owner;
my $table_name;
my $ignore_empty;
my $year = ((localtime())[5]+1900); # Copyright Year
my $start_time=time();              # Start time
my $file_count=0;                   # File counter
my $one_shot=0;                     # One shot flag

#----------------------------------------------------------------------------------#
# Prints the version of this script and exits the program
sub version_display{
  print '$Header: ScriptData.pl 1.5 2005/04/05 15:23:44BST ghoekstra DEV  $'."\n";
  exit(0);
}

#----------------------------------------------------------------------------------#
# Get all columns for table
sub get_table_columns{
  my ($connection,$cursor,$owner,$table)=@_;
  my $sql=
      "select * ".
      "  from sys.all_tab_columns".(defined($dblink)?'\@'.$dblink:'').
      " where table_name=upper(".$connection->quote($table).") ".
      "   and owner=upper(".$connection->quote($owner).") ".
      " order by owner,table_name,column_id";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting columns details of table $owner.$table".(defined($dblink)?'\@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get all values for table
# Order by primary key of one exists
sub get_table_values{
  my ($connection,$cursor,$owner,$table)=@_;
  my $sql="select * from $owner.$table".(defined($dblink)?'\@'.$dblink:'');
  # Get Primary key columns for this table
  my @pk=$connection->primary_key(undef,$owner,$table);
  my $pk_cols = join(',',@pk);
  if(@pk>0){
    # This table has columns in the primary key - let's be nice and order to them
    $sql.=" order by $pk_cols";
  }else{
    # This table has no primary key - order onthe first column
    $sql.=" order by 1 asc";
  }
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting values from table $owner.$table".(defined($dblink)?'\@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Script to spreadsheet
# Columns: Column name, data type(size), nullable, comment
sub ScriptSpreadsheet{
  use Spreadsheet::WriteExcel;
  # We now have a list of all the tables which to create CREATION scripts for:
  for(my $i=0;$i<scalar(@schema_tables);$i+=2){
    my $owner=uc(@schema_tables[$i]);
    my $table=uc(@schema_tables[$i+1]);

    # Make up file name
    my $short_file_name=lc($table).".xls";
    my $file_name = lc($owner).".metadata.".lc($table).".xls";
    print "Building Excel report for table $owner.$table".(defined($dblink)?'\@'.$dblink:'')." in file $short_file_name\n";

    # Create a new workbook and add a worksheet
    my $workbook  = Spreadsheet::WriteExcel->new($file_name);
    $file_count++;
    my $sheet_name = lc("$owner.$table");
    if(length($sheet_name)>30){
      $sheet_name= substr($sheet_name,0,29)."..";
    }
    my $worksheet = $workbook->addworksheet($sheet_name);

    # Create a format for the column headings
    my $header = $workbook->addformat();
    $header->set_bold();
    $header->set_size(10);
    $header->set_bg_color('gray');
    my $comment_style = $workbook->addformat();
    $comment_style->set_italic();
    $comment_style->set_size(8);
    my $date_style = $workbook->addformat();
    $date_style->set_num_format('00000000000000');

    # Header
    my $c_columns;
    $c_columns=get_table_columns($dbh, $c_columns, $owner, $table);
    my $col_count=0;
    my $row_cols_ref;
    while($row_cols_ref=$c_columns->fetchrow_hashref()){
      $worksheet->write(0, $col_count, $row_cols_ref->{COLUMN_NAME},$header);
      my $width;
      my $size = $row_cols_ref->{DATA_TYPE};
      # Precision
      if(defined $row_cols_ref->{DATA_PRECISION} && $row_cols_ref->{DATA_PRECISION}>0){
        if(defined $row_cols_ref->{DATA_SCALE} && $row_cols_ref->{DATA_SCALE}>0){
          $size.="($row_cols_ref->{DATA_PRECISION},$row_cols_ref->{DATA_SCALE})";
          $width=$row_cols_ref->{DATA_PRECISION}+$row_cols_ref->{DATA_SCALE};
        }else{
          # Data scale is 0 - ignore
          $size.="($row_cols_ref->{DATA_PRECISION})";
          $width=$row_cols_ref->{DATA_PRECISION}
        }
      }else{
        # Only show precision for non-binary and non-date
        if(!($row_cols_ref->{DATA_TYPE}=~/DATE|LOB|RAW|LONG|BFILE|ROWID|XML/)){
          $size.="($row_cols_ref->{DATA_LENGTH})";
          $width=$row_cols_ref->{DATA_LENGTH}
        }
      }
      $worksheet->write(1, $col_count, $size,$comment_style);
      # Set column width
      $width=($width>40)?40:$width;
      $width=($width<length($row_cols_ref->{COLUMN_NAME})*3/2)?length($row_cols_ref->{COLUMN_NAME})*3/2:$width;
      $worksheet->set_column($col_count, $col_count, $width);
      # Set date format
      if($row_cols_ref->{DATA_TYPE}=~/DATE/){

        $worksheet->set_column($col_count, $col_count, 18, $date_style);
      }
      $col_count++;
    }

    # Get table values
    my $c_values;
    $c_values=get_table_values($dbh, $c_values, $owner, $table);
    my $row_count=2;
    while(my @row_init=$c_values->fetchrow_array()){
      for(my $i=0;$i<(scalar @row_init);$i++){
        my $value=@row_init[$i];
        # Prevent spreadsheet that this is actual formula
        if($value=~/^(=|\+|-|\/|\*|\.|\@|%|\^)/){
          $value="'$value";
        }
        $worksheet->write($row_count,$i,$value);
      }
      $row_count++;
    }
    $workbook->close();

    # Split file into directory tree
    $file_name=~/(.+)\.(.+)\.(.+\..+)/;
    if(!-e $1 && -d _){
      mkdir(qq|$1|,755);
      chmod(777,$1);
    }
    if(!-e q|$1/$2| &&  -d _){
      mkdir(qq|$1/$2|,755);
      chmod(777,q|$1/$2|);
    }
    mkdir(qq|$1|,755);
    mkdir(qq|$1/$2|,755);
    move($file_name,qq|$1/$2/$short_file_name|) || die "Could not move temp file to $1/$2/$short_file_name. Error $!\n";
  }
}

#----------------------------------------------------------------------------------#
# Script CSV file
sub ScriptCSV{
  # We now have a list of all the tables which to create INITIALISATION scripts for:
  for(my $i=0;$i<scalar(@schema_tables);$i+=2){
    my $owner=lc(@schema_tables[$i]);
    my $table=lc(@schema_tables[$i+1]);

    # Ignore empty tables
    my $sth_count=$dbh->prepare("select count(*) from $owner.$table".(defined($dblink)?'\@'.$dblink:''));
    $sth_count->execute();
    @row=$sth_count->fetchrow_array();
    $sth_count->finish();
    my $total_rows = @row[0];
    if($total_rows>0 || !$ignore_empty){
      # Table has useful data in it, or we should not ignore it if it is empty.

      # Make up file name
      my $short_file_name="$table.csv";
      my $file_name = "$owner.data.$table.csv";
      print "Building CSV file for table $owner.$table in file $short_file_name\n";
      open(F,"+>".$file_name) || die "Could not open temporary file $file_name for writing. $!\n";
      $file_count++;
      # Get all columns for table
      my $c_columns;
      $c_columns=get_table_columns($dbh, $c_columns, $owner, $table);
      # TODO: Use @data_types = $c_columns->{TYPE} once supported by DBI for Oracle
      my ($row_cols_ref,@cols,@data_types);
      while($row_cols_ref=$c_columns->fetchrow_hashref()){
        push(@cols,$row_cols_ref->{COLUMN_NAME});
        push(@data_types,$row_cols_ref->{DATA_TYPE});
      }
      if(defined $csvheader){
        print join(@cols,$csvseparator)."\n";
      }

      # Get table values
      my $c_values;
      $c_values=get_table_values($dbh, $c_values, $owner, $table);
      my $row_count=0;
      while(my @row_init=$c_values->fetchrow_array()){

        $sql='';
        for(my $i=0;$i<(scalar @row_init);$i++){
          # Value separator
          $sql.=$csvseparator if($i>0);
          my $value=@row_init[$i];
          # Column data types
          if(@data_types[$i]=~/CHAR/){
            if(!defined $value){
              $sql.="NULL";
            }else{
              $value=$value;
              # Explicit Carriage Returns and Line Feeds in text data
              $value=~s/\r/'\r'/eg;
              $value=~s/\n/'\n'/eg;
        # Escape the separator
        if(defined $csvseparator){
          $value=~s/$csvseparator/\\$csvseparator/;
              }
              $sql.=$value;
            }
          }
          elsif(@data_types[$i]=~/DATE/){
            if(!defined $value){
              $sql.="NULL";
            }else{
              $sql.=$value;
            }
          }
          elsif(@data_types[$i]=~/NUMBER/){
            if(!defined $value){
              $sql.="NULL";
            }else{
              $sql.=$value;
            }
          }
          elsif(@data_types[$i]=~/FLOAT/){
            if(!defined $value){
              $sql.="NULL";
            }else{
              $sql.=$value;
            }
          }
          else {die "* Oracle datatype @data_types[$i] of column @cols[$i] not yet supported\n";}
        }#..for
        $sql.="\n";
        print F $sql;
      }#..while
      $c_values->finish();
      close F;

      if($debug){
         # Display files
         open(F,"<".$file_name)||die "Could not open $file_name for display. $!\n";
         my @lines=<F>;
         close F;
         foreach(@lines){print "$_\n";}
      }
      print "$total_rows records.\n";

      # Split file into directory tree
      $file_name=~/(.+)\.(.+)\.(.+\..+)/;
      if(!-e $1 && -d _){
  mkdir(qq|$1|,755);
  chmod(777,$1);
      }
      if(!-e q|$1/$2| &&  -d _){
  mkdir(qq|$1/$2|,755);
  chmod(777,q|$1/$2|);
      }
      mkdir(qq|$1|,755);
      mkdir(qq|$1/$2|,755);
      move($file_name,qq|$1/$2/$short_file_name|) || die "Could not move temp file to $1/$2/$short_file_name. Error $!\n";
    }else{
      print "Ignoring table $owner.$table".(defined($dblink)?'\@'.$dblink:'').", as it is empty\n" if($verbose);
    }
  }
}

#----------------------------------------------------------------------------------#
# Script SQL Creation file
sub ScriptSQL{
  # We now have a list of all the tables which to create INITIALISATION scripts for:
  for(my $i=0;$i<scalar(@schema_tables);$i+=2){
    my $owner=lc(@schema_tables[$i]);
    my $table=lc(@schema_tables[$i+1]);

    # Ignore empty tables
    my $sth_count=$dbh->prepare("select count(*) from $owner.$table".(defined($dblink)?'\@'.$dblink:''));
    $sth_count->execute();
    @row=$sth_count->fetchrow_array();
    $sth_count->finish();
    my $total_rows = @row[0];
    if($total_rows>0 || !$ignore_empty){
      # Table has useful data in it, or we should not ignore it if it is empty.

      # Make up file name
      my $short_file_name="$table.sql";
      my $file_name = "$owner.data.$table.sql";
      Oracle::Script::Common->info("Building data initialisation script for table $owner.$table in file $short_file_name\n") if ! $quiet;
      open(F,"+>".$file_name) || die "Could not open temporary file $file_name for writing. $!\n";
      $file_count++;
      print F Oracle::Script::FileHeaders->MakeSQLFileHeader($file_name,$owner,$company_name);
      print F "-- Data population script for table $owner.$table.\n";
      print F "-- WARNING: *** This script overwrites the entire table! ***\n";
      print F "--          *** Save important content before running.   ***\n";
      print F "-- To run this script from the command line:\n";
      print F "--   \$ sqlplus \"$owner/[password]@[instance]\" \@$short_file_name\n";
      print F Oracle::Script::FileHeaders->OracleDBDetails($userid,$password,$instance,'--',$dblink);
      print F "------------------------------------------------------------------------------\n";
      print F "set feedback off;\n";
      print F "prompt Populating $total_rows records into table $owner.$table.\n";
      print F "\n";
      print F "-- Truncate the table:\n";
      print F "truncate table $owner.$table;\n";
      print F "\n";
      print F "------------------------------------------------------------------------------\n";
      print F "-- Populating the table:\n";
      print F "------------------------------------------------------------------------------\n";
      print F "\n";
      print F "--{{BEGIN AUTOGENERATED CODE}}\n";
      print F "\n";


      # Get all columns for table
      my $c_columns;
      $c_columns=get_table_columns($dbh, $c_columns, $owner, $table);

      # TODO: Use @data_types = $c_columns->{TYPE} once supported by DBI for Oracle
      my ($row_cols_ref,@cols,@data_types);
      while($row_cols_ref=$c_columns->fetchrow_hashref()){
        push(@cols,$row_cols_ref->{COLUMN_NAME});
        push(@data_types,$row_cols_ref->{DATA_TYPE});
      }

      # Get table values
      my $c_values;
      $c_values=get_table_values($dbh, $c_values, $owner, $table);

      # Make up INSERT statement
      my $row_count=0;
      while(my @row_init=$c_values->fetchrow_array()){

        # Add progress bar
        if($total_rows > 1000 && !defined($verbose)){
          if(($row_count%($total_rows/10))==0){
            print F sprintf("prompt %d %%\n",((($row_count/($total_rows/10))*10)+0.99999));
          }
        }

        # Commit every 100 rows
        $row_count++;
        if(($row_count%100)==0){
          print F "commit;\n";
        }

        $sql="insert into ".$owner.".".$table."\n      (".join(',',@cols).")\nvalues(";
        for(my $i=0;$i<(scalar @row_init);$i++){
          # Value separator
          $sql.="," if($i>0);
          my $value=@row_init[$i];
          # Column data types
          if(@data_types[$i]=~/CHAR/){
            if(!defined $value){
              $sql.="NULL";
            }else{
              $value=$dbh->quote($value);
              # Make ampersants in text data not revert to substitution when running in SQLPLUS
              # by replacing it with the ASCII code -  Can also escape ampersants - might this be a better idea?
              $value=~s/&/{$dbh->quote('||chr(38)||')}/eg;
              # Explicit Carriage Returns and Line Feeds in text data
              #$value=~s/\r\n/{$dbh->quote('||chr(13)||chr(10)||')}/eg;
              #$value=~s/\r/{$dbh->quote('||chr(13)||')}/eg;
              $value=~s/\n/{$dbh->quote('||chr(10)||')}/eg;
              # Make data line break appear as SQL line breaks
              $value=~s/(\|\|chr\(10\)\|\|)/"$1\n      "/eg;
              # Insert newline if this is going to be a long string
              $sql.="\n      ";
              $sql.=$value;
            }
          }
          elsif(@data_types[$i]=~/DATE/){
            if(!defined $value){
              $sql.="NULL";
            }else{
              $sql.="to_date(".$dbh->quote($value).",'YYYYMMDDHH24MISS')";
            }
          }
          elsif(@data_types[$i]=~/NUMBER/){
            if(!defined $value){
              $sql.="NULL";
            }else{
              $sql.=$value;
            }
          }
          elsif(@data_types[$i]=~/FLOAT/){
            if(!defined $value){
              $sql.="NULL";
            }else{
              $sql.=$value;
            }
          }
          else {die "* Oracle datatype @data_types[$i] of column @cols[$i] not yet supported\n";}
        }#..for
        $sql.="\n      );\n";
        print F $sql;
      }#..while
      $c_values->finish();


      print F "\n";
      print F "--{{END AUTOGENERATED CODE}}\n";
      print F "\n";
      print F "commit;\n";
      print F "set feedback on;\n";
      print F Oracle::Script::FileHeaders->MakeSQLFileFooter($file_name);
      close F;
      print "$row_count records imported.\n" if($verbose);

      if($debug){
         # Display files
         open(F,"<".$file_name)||die "Could not open $file_name for display. $!\n";
         my @lines=<F>;
         close F;
         foreach(@lines){Oracle::Script::Common->debug("$_");}
      }
      print "$total_rows records.\n";
      # Split file into directory tree
      Oracle::Script::Common->file2tree($file_name,$short_file_name);

    }else{
      print "Ignoring table $owner.$table".(defined($dblink)?'\@'.$dblink:'').", as it is empty\n" if($verbose);
    }
  }
}


# Main Program
GetOptions( 'instance|i=s'=>\$instance,
            'user|u=s'    =>\$userid,
            'password|p=s'=>\$password,
            'dblink|l=s'  =>\$dblink,
            'schemas|s=s' =>\@meta_schemas,
            'objects|o=s' =>\@objects,
            'debug|d'     =>\$debug,
            'ignoreempty' =>\$ignore_empty,
            'author=s'    =>\$author,
            'contributors'=>\$contributors,
            'version|v'   =>\$version_display,
            'verbose'     =>\$verbose,
            'gnu'         =>\$gnu,
            'spreadsheet|x'=>\$excel,
            'csv'         =>\$csv,
            'csvseperator=s'=>\$csvseparator,
            'csvlinefeed=s'=>\$csvlinefeed,
            'csvheader'   =>\$csvheader,
            'quiet'       =>\$quiet,
            'help|?'      =>\$help,
            'man'         =>\$man) || pod2usage(2);
             pod2usage(1) if $help;
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
$meta_tables=join(',',@objects);
$meta_tables=~s/\s//;
$meta_tables=~tr/a-z/A-Z/;
$verbose=1 if($debug);

if(!defined $csv and (defined $csvseparator || defined $csvheader)){
  $csv=1;
}
if(!defined $csvseparator){
  $csvseparator=',';
}

# Connect to the database
print "Connecting to Database $instance..." if($verbose);
$dbh = DBI->connect("dbi:Oracle:$instance", $userid, $password)
  || die "Unable to connect to $instance: $DBI::errstr\n";
print "Connected.\n" if($verbose);

# We want dates to appear in nice text form
$dbh->do("ALTER SESSION SET NLS_DATE_FORMAT = 'YYYYMMDDHH24MISS'")
  || die "You do not seem to have access rights to ALTER SESSIONS SET NLS_FORMAT\n";

# Anticipate long values
$dbh->{LongReadLen} = 512 * 1024;
$dbh->{LongTruncOk} = 1;

if(defined($dblink)){
  $dblink=Oracle::Script::Common->get_dblink_full_name($dbh,$dblink);
}

# -o parameter:
# Get all individually specified tables
if(defined $meta_tables){
  my @spec_tables=split(/,/,$meta_tables);
  foreach my $table(@spec_tables){
    my @schema_table=split(/\./,$table);
    # Where no schema name is defined, default to the user login schema
    if(!exists $schema_table[1]){
      push(@schema_table,@schema_table[0]);
      @schema_table[0]=$userid;
    }
    print "Individually specified table: @schema_table[0].@schema_table[1]\n" if($verbose);
    # Check if this table exists
    my $sth=$dbh->prepare(
        "select distinct owner, table_name ".
        "  from sys.all_tables".(defined($dblink)?'\@'.$dblink:'').
        " where owner=upper(".$dbh->quote(@schema_table[0]).") ".
        "   and table_name=upper(".$dbh->quote(@schema_table[1]).") ".
        "   and table_name not like ".$dbh->quote('%$%').
        "   and table_name not like ".$dbh->quote('%/%').
        " order by 1,2"
    );
    $sth->execute();
    # Fetch single record
    @row=$sth->fetchrow_array();
    if(scalar(@row)==0){
      print "* Individually specified table @schema_table[0].@schema_table[1] does not exist\n";
    }else{
      push(@schema_tables,@row);
    }
    $sth->finish();
  }
}

# -m parameter:
# Get all schemas for which table create scripts will be created, if any schemas are defined at all
# You may have specified other schemas, but either they don't exist or they don't have any tables in them
if(defined $meta_schemas){
  # Get all the tables that belong to the schemas
  my $sth=$dbh->prepare(
      "select distinct owner, table_name".
      "  from sys.all_tables".(defined($dblink)?'\@'.$dblink:'').
      " where instr(upper(".$dbh->quote($meta_schemas)."),OWNER) <> 0".
      "   and table_name <> 'PLAN_TABLE'".
      "   and table_name not like ".$dbh->quote('%$%').
      "   and table_name not like ".$dbh->quote('%/%').
      " order by owner,table_name"
  );
  $sth->execute();
  my $tables_ref = $sth->fetchall_arrayref();
  foreach my $row(@{$tables_ref}){
    my ($schema,$table) = @{$row};
    print "Table specified by schema: $schema.$table".(defined($dblink)?'\@'.$dblink:'')."\n" if($verbose);
    push(@schema_tables,$schema);
    push(@schema_tables,$table);
  }
  $sth->finish();
}

# Default, if no schemas or tables have been defined
if(!defined $meta_tables && !defined $meta_schemas){
  print "Creating files for all tables in schema $userid.\n" if($verbose);
  # Check if this table exists
  my $sth=$dbh->prepare(
      "select distinct owner, table_name ".
      "  from sys.all_tables".(defined($dblink)?'\@'.$dblink:'').
      " where owner=upper(".$dbh->quote($userid).")" .
      "   and table_name <> 'PLAN_TABLE' ".
      "   and table_name not like ".$dbh->quote('%$%').
      "   and table_name not like ".$dbh->quote('%/%').
      " order by 1,2");
  $sth->execute();
  my $tables_ref = $sth->fetchall_arrayref();
  foreach my $row(@{$tables_ref}){
    my ($schema,$table) = @{$row};
    print "Default table for login schema $userid: $schema.$table".(defined($dblink)?'\@'.$dblink:'')."\n" if($verbose);
    push(@schema_tables,$schema);
    push(@schema_tables,$table);
  }
  $sth->finish();
}

if(defined $excel){
  ScriptSpreadsheet;
}
if(defined $csv){
  ScriptCSV;
}
if(!defined $excel and !defined $csv){
  ScriptSQL;
}


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

ScriptData.pl - Generates formal population scripts for tables

=head1 SYNOPSIS

=over 4

=item B<ScriptData.pl> B<-i> db1 B<-u> user B<-p> passwd

Builds the population scripts for all the tables in the
schema 'user' on database instance db1.

=item B<ScriptData.pl> B<-i> db1 B<-u> user B<-p> passswd B<-m> schema1 B<-m> schema2

Builds the population scripts only for all the tables in
the schemas 'schema1' and 'schema2' on database instance db1.
Use this form if the required schema does not have select
rights to SYS.ALL_... views, and use a system user to log with.

=item B<ScriptData.pl> B<-i> db1 B<-u> user B<-p> passwd B<-t> schema1.table1

Builds the population scripts only for the table 'schema1.table1'
on database instance db1.

=item B<ScriptData.pl> B<-i> db1 B<-u> user B<-p> passwd -l db2

Builds the population scripts for all the tables in the DBLink's
default schemas of the remote database instance, which is accessed
from this database instance db1 via database link db2.

=item B<ScriptData.pl> B<-i> db1 B<-u> user B<-p> passwd B<-m> schema1,schema2 B<-l> db2

Builds the population scripts for all the tables in the schemas 'schema1'
and 'schema2' on a remote database instance that is accessed from this
Oracle instance db1 via the database link db2.

=head1 OPTIONS AND ARGUMENTS

B<ScriptData.pl> B<-u|--user> UserId B<-p|--password> Passwd [B<-i|--instance> Instance name]
[-l|--dblink DBLink] [-s|--schemas Schemas] [-o|--objects Tables] [--IgnoreEmpty]
[-x|--spreadsheet|[[-c|--csv] [--csvseperator Seperator] [--csvheader]]]
[--contributors] [-v|--version] [--author author name] [--gnu] [--quiet|--verbose|--debug] [-?|--help] [--man]


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

Schema name(s) for which the tables will be scripted out.
Either use -m schema1 -m schema2 or -m schema1,schema2.

=item B<-o|--objects List of table names>

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

Ignore empty tables

=item B<-x|--spreadsheet>

Create a Spreadsheet report of the objects

=item B<-c|--csv>

Create a comma-separated variable file

=item B<--csvseperator Seperator string>

The character string to use to separate the value in the CSV file. Defaults to ','.

=item B<--csvlinefeed Hex Linefeed string>

The hex string to use to separate lines in the CSV file. Defaults to UNIX-based '0A'.
For a Windows-based file set it to '0D0A' and for Mac-based file set it to '0A0D'.

=item B<--csvheader>

Include a comma-separated header in the first line of the file corresponding to the table that is scripted.

=item B<--csvfooter>

Include a footer on the last line of the file. This line contains the number of records.

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

B<2.> Make date format consistent.

B<3.> Deal in a nice way with tables that use a sequence-based keys

B<4.> Deal with column types BLOB's, CLOB's, LOB's, RAW's, XML types, BFILE's, ROWID's, XML

B<5.> Deal with ownership of directory creation on Unix

B<6.> Allow for Column-width based CSV files

B<7.> Implement CSV files

B<8.> Command-line interfaces needs some fixing

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
