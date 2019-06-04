#!/usr/bin/perl
#----------------------------------------------------------------------------------#
#----------------------------------------------------------------------------------#
# FUNCTION:
# Scripts the creation scripts of Oracle tables into nice installation files.
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
my @schema_tables;                  # Schema Table list
my $cmd;
my $table_owner;
my $table_name;
my $ignore_empty;
my $year = ((localtime())[5]+1900); # Copyright Year
my $start_time=time();              # Start time
my $file_count=0;                   # File counter
my $one_shot=0;                     # One shot flag
my $two_shot=0;                     #

# Command Line parameters
my ($instance,$meta_schemas,@meta_schemas,$meta_tables,@objects,$userid,$password,$author,$verbose,$contributors,$version_display,$debug,$excel,$dblink,$quiet,$man,$help,$gnu,$grants,$no_storage);

#----------------------------------------------------------------------------------#
# Prints the version of this script and exits the program
sub version_display{
  print '$Header: ScriptTables.pl 1.8 2005/03/03 11:31:14GMT ghoekstra DEV  $'."\n";
  exit(0);
}

#----------------------------------------------------------------------------------#
# Get all details for table
sub get_table_details{
  my ($connection,$cursor,$owner,$table)=@_;
  my $sql=
      "select * ".
      "  from sys.all_tables".(defined($dblink)?'\@'.$dblink:'').
      " where table_name=upper(".$connection->quote($table).") ".
      "   and owner=upper(".$connection->quote($owner).") ";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting table details of table $owner.$table".(defined($dblink)?'\@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
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

#------------------------$dblink----------------------------------------------------------#
# Get columns report for table
sub get_table_col_report{
  my ($connection,$cursor,$owner,$table)=@_;
  my $sql=
    "select tc.column_name,  ".
    "       tc.data_type, ".
    "       tc.data_length, ".
    "       tc.data_precision, ".
    "       tc.data_scale,  ".
    "       tc.nullable, ".
    "       co.comments ".
    " from sys.all_tab_columns".(defined($dblink)?'\@'.$dblink:'').'  tc,'.
    "      sys.all_col_comments".(defined($dblink)?'\@'.$dblink:'').' co '.
    "where tc.owner = co.owner ".
    "  and tc.table_name = co.table_name ".
    "  and tc.column_name = co.column_name ".
    "  and tc.table_name=upper(".$connection->quote($table).") ".
    "  and tc.owner=upper(".$connection->quote($owner).") ".
    "order by tc.column_id ";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting columns report for table $owner.$table".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get the partitioned details for each table
sub get_table_partitions{
  my ($connection,$cursor,$owner,$table)=@_;
  my $sql=
      "select distinct ".
      "       t.partitioning_type    as partitioning_type, ".
      "       t.def_tablespace_name  as def_tablespace_name, ".
      "       c.column_name          as column_name, ".
      "       nvl(p.partition_name,s.partition_name) as partition_name,".
      "       t.subpartitioning_type as subpartition_type ".
      "  from sys.all_part_tables".(defined($dblink)?'\@'.$dblink:'').'         t '.
      "     , sys.all_part_key_columns".(defined($dblink)?'\@'.$dblink:'').'    c '.
      "     , sys.all_part_col_statistics".(defined($dblink)?'\@'.$dblink:'').' p '.
      "     , sys.all_tab_subpartitions".(defined($dblink)?'\@'.$dblink:'').'   s '.
      " where t.owner      = c.owner ".
      "   and t.table_name = c.name ".
      "   and t.owner      = p.owner(+) ".
      "   and t.table_name = p.table_name(+) ".
      "   and s.table_owner(+) = t.owner ".
      "   and s.table_name(+)  = t.table_name ".
      "   and t.owner      = ".$connection->quote($owner).
      "   and t.table_name = ".$connection->quote($table).
      "   and rtrim(c.object_type) = 'TABLE' ";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting partition details of table $owner.$table".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get the details of subpartitioned
sub get_subpartition_details {
  my ($connection,$cursor,$owner,$table,$partition)=@_;
  my $sql=
    "select t.subpartition_name as subpartition_name, ".
    "       t.high_value        as high_value ".
    "  from sys.all_tab_subpartitions ".(defined($dblink)?'\@'.$dblink:'').'         t '.
    " where t.table_owner = ".$connection->quote($owner).
    "   and t.table_name  = ".$connection->quote($table).
    "   and t.partition_name = ".$connection->quote($partition).
    " order by t.subpartition_position";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting subpartition details of table $owner.$table".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}


#----------------------------------------------------------------------------------#
# Get the details of subpartitioned
sub get_index_subpartition_details {
  my ($connection,$cursor,$index_owner,$index_name,$partition)=@_;
  my $sql=
    " select * ".
    "   from sys.all_ind_subpartitions ".(defined($dblink)?'\@'.$dblink:'').'         t '.
    "  where t.partition_name = ".$connection->quote($partition).
    "    and t.index_owner    = ".$connection->quote($index_owner).
    "    and t.index_name     = ".$connection->quote($index_name);
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting subpartitions details of index $index_name".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}


#----------------------------------------------------------------------------------#
# Get the user-generated constraints for a table
sub get_table_constraints{
  my ($connection,$cursor,$owner,$table)=@_;
  my $sql=
    "select * ".
    "  from sys.all_constraints".(defined($dblink)?'\@'.$dblink:'').
    " where owner      = ".$connection->quote($owner).
    "   and table_name = ".$connection->quote($table).
    "   and generated  = 'USER NAME' ".
    " order by constraint_type, constraint_name";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting table constraints for table $owner.$table".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get the columns of a constraint
sub get_column_constraints{
  my ($connection,$cursor,$owner,$table, $constraint)=@_;
  my $sql=
    "select * ".
    "  from sys.all_cons_columns".(defined($dblink)?'\@'.$dblink:'').
    " where owner           = ".$connection->quote($owner).
    "   and table_name      = ".$connection->quote($table).
    "   and constraint_name = ".$connection->quote($constraint).
    " order by position ";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting column constraints for table $owner.$table".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get the columns of a referenced key
sub get_referenced_key_column{
  my ($connection,$cursor,$constraint)=@_;
  my $sql=
    "select * ".
    "  from sys.all_cons_columns".(defined($dblink)?'\@'.$dblink:'').
    " where constraint_name = ".$connection->quote($constraint).
    " order by position ";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting column of a referenced key $constraint".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get Indexes that are not already used as primary and unique constraints
sub get_table_indexes{
  my ($connection,$cursor,$owner,$table)=@_;
  my $sql=
    "select * ".
    "  from sys.all_indexes".(defined($dblink)?'\@'.$dblink:'').
    " where table_owner = ".$connection->quote($owner).
    "   and table_name  = ".$connection->quote($table).
    "   and index_name not in ".
    "        (select constraint_name from sys.all_constraints".(defined($dblink)?'\@'.$dblink:'').") ".
    " order by index_name";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting table indexes for table $owner.$table".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get Index Partitions
sub get_index_partitions{
  my ($connection,$cursor,$index)=@_;
  my $sql=
    "select * ".
    "  from sys.all_ind_partitions".(defined($dblink)?'\@'.$dblink:'').
    " where index_name = ".$connection->quote($index).
    " order by partition_position";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting index partitions for index $index.\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get index columns
sub get_index_columns{
  my ($connection,$cursor,$owner,$table,$index)=@_;
  my $sql=
    "select * ".
    "  from sys.all_ind_columns".(defined($dblink)?'\@'.$dblink:'').
    " where table_owner = ".$connection->quote($owner).
    "   and table_name  = ".$connection->quote($table).
    "   and index_name  = ".$connection->quote($index).
    " order by column_position";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting index columns for table $owner.$table".(defined($dblink)?'@'.$dblink:'')." index $index.\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get Table Grantees
sub get_table_grantees{
  my ($connection,$cursor,$owner,$table)=@_;
  my $sql=  "select GRANTEE ".
                " , count(*) as grant_count ".
             " from sys.all_tab_privs".(defined($dblink)?'\@'.$dblink:'').
            " where table_schema = ".$connection->quote($owner).
              " and table_name = ".$connection->quote($table).
            " group by GRANTEE ".
            " order by 1";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting table grantees for table $owner.$table".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get Table Grants
sub get_table_grants{
  my ($connection,$cursor,$owner,$table,$grantee)=@_;
  my $sql=  "select * ".
             " from sys.all_tab_privs".(defined($dblink)?'\@'.$dblink:'').
            " where grantee = ".$connection->quote($grantee).
              " and table_schema = ".$connection->quote($owner).
              " and table_name = ".$connection->quote($table).
            " order by privilege";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting table grants for table $owner.$table".(defined($dblink)?'@'.$dblink:'')." grantee $grantee.\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get the high_value for the partition
sub get_partition_highvalues{
  my ($connection,$cursor,$owner,$table,$partition_name)=@_;
  my $sql=  "select high_value ".
             " from sys.all_tab_partitions".(defined($dblink)?'\@'.$dblink:'').
            " where table_name     = ".$connection->quote($table).
              " and table_owner    = ".$connection->quote($owner).
              " and partition_name = ".$connection->quote($partition_name);
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting high_value for the partitioned table $owner.$table".(defined($dblink)?'@'.$dblink:'')." partition $partition_name.\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get Tablespace, physical and storage attributes clause
sub get_partition_storage{
  my ($connection,$cursor,$owner,$table,$partition_name)=@_;
  my $sql=  "select * ".
             " from sys.all_tab_partitions".(defined($dblink)?'\@'.$dblink:'').
            " where table_owner    = ".$connection->quote($owner).
              " and table_name     = ".$connection->quote($table).
              " and partition_name = ".$connection->quote($partition_name);
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting partition storage for the partitioned table $owner.$table".(defined($dblink)?'@'.$dblink:'')." partition $partition_name.\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get Table comments
sub get_table_comments{
  my ($connection,$cursor,$owner,$table)=@_;
  my $sql=
    "select comments ".
    "  from sys.all_tab_comments".(defined($dblink)?'\@'.$dblink:'').
    " where owner = ".$connection->quote($owner).
    "   and table_name = ".$connection->quote($table);
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting table comments for table $owner.$table".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get column comments
sub get_column_comments{
  my ($connection,$cursor,$owner,$table,$column)=@_;
  my $sql=
      "select comments ".
      "  from sys.all_col_comments".(defined($dblink)?'\@'.$dblink:'').
      " where owner       = ".$connection->quote($owner).
      "   and table_name  = ".$connection->quote($table).
      "   and column_name = ".$connection->quote($column);
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting column comments for table $owner.$table".(defined($dblink)?'@'.$dblink:'')."\n".$cursor->errstr()."\n";
  return $cursor;
}


#----------------------------------------------------------------------------------#
# Get remote constraint name for a given foreign key constraint
sub get_remote_constraint_table_key_name{
  my ($connection,$cursor,$constraint_name)=@_;
  my $sql="select r_constraint_name ".
          "  from sys.all_constraints ".
          " where constraint_name = ".$dbh->quote($constraint_name);
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting remote constraint name for contraint $constraint_name\n".$cursor->errstr()."\n";
  return $cursor;
}


#----------------------------------------------------------------------------------#
# Checks if table exists
sub does_table_exist{
  my ($connection,$cursor,$owner,$table)=@_;
  my $sql=
        "select distinct owner, table_name ".
        "  from sys.all_tables".(defined($dblink)?'\@'.$dblink:'').
        " where owner=upper(".$dbh->quote($owner).") ".
        "   and table_name=upper(".$dbh->quote($table).") ".
        "   and table_name not like '%\$%' ".
        "   and table_name not like '%/%' ".
        " order by 1,2";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error checking if table $owner.$table exists.\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Get all scriptable tables for the string of schemas
sub get_scriptable_tables{
  my ($connection,$cursor,$schemas)=@_;
  my $sql=
      "select distinct owner, table_name".
      "  from sys.all_tables".(defined($dblink)?'\@'.$dblink:'').
      " where instr(upper(".$dbh->quote($schemas)."),OWNER) <> 0".
      "   and table_name <> 'PLAN_TABLE'".
      "   and table_name not like '%\$%' ".
      "   and table_name not like '%/%' ".
      "   and table_name not like 'TOAD_PLAN%' ".
      " order by owner,table_name";
  $cursor=$connection->prepare($sql);
  $cursor->execute() || die "Error getting all scriptable tables for the string of schemas [$schemas].\n".$cursor->errstr()."\n";
  return $cursor;
}

#----------------------------------------------------------------------------------#
# Script to spreadsheet
# Columns: Column name, data type(size), nullable, comment
sub ScriptSpreadsheet{
  use Spreadsheet::WriteExcel;
  # We now have a list of all the tables to create CREATION scripts for:
  foreach (@schema_tables){
    my $owner=$_->{"schema"};
    my $table=$_->{"object"};

    my $c_table;
    $c_table=get_table_details($dbh, $c_table, $owner, $table);
    my $table_row_ref=$c_table->fetchrow_hashref();

    # Make up file name
    my $short_file_name=lc($table).".xls";
    my $file_name = lc($owner).".tables.".lc($table).".xls";
    print "Building spreadsheet report for table $owner.$table".(defined($dblink)?'\@'.$dblink:'')." in file $short_file_name\n" if(!$quiet);
    $file_count++;

    # Create a new workbook and add a worksheet
    unlink $file_name;
    my $workbook  = Spreadsheet::WriteExcel->new($file_name);
    my $sheet_name = lc("$owner.$table");
    if(length($sheet_name)>30){
      $sheet_name= substr($sheet_name,0,29)."..";
    }
    my $worksheet = $workbook->addworksheet($sheet_name);
    $worksheet->set_landscape();
    $worksheet->fit_to_pages(1,1);


    # Set the column widths
    $worksheet->set_column(0, 0, 20);
    $worksheet->set_column(1, 1, 20);
    $worksheet->set_column(2, 2, 20);
    $worksheet->set_column(3, 3, 60);

    # Create a format for the table headings
    my $tab_header = $workbook->addformat();
    $tab_header->set_bold();
    $tab_header->set_size(12);

    # Create a format for the table headings
    my $header = $workbook->addformat();
    $header->set_bold();
    $header->set_size(10);
    $header->set_bg_color('gray');

    # Create a format for the column headings
    my $col_header = $workbook->addformat();
    $col_header->set_bold();
    $col_header->set_size(10);
    $col_header->set_bg_color('yellow');

    my $offset = 0;
    $worksheet->write($offset, 0, 'Schema:',$header);
    $worksheet->write($offset, 1, 'Table:',$header);
    $worksheet->write($offset, 2, 'Type',$header);
    $worksheet->write($offset, 3, 'Table Description:',$header);
    $offset++;
    $worksheet->write($offset, 0, $owner, $tab_header);
    $worksheet->write($offset, 1, $table, $tab_header);
    if($table_row_ref->{TEMPORARY}=~/Y/){
      $worksheet->write($offset, 2, 'Temporary');
    }

    # Get table comment
    my $c_tc;
    $c_tc=get_table_comments($dbh, $c_tc, $owner, $table);
    my $tc_row_ref = $c_tc->fetchrow_hashref();
    if(defined $tc_row_ref){
      $worksheet->write($offset, 3, $tc_row_ref->{COMMENTS});
    }

    # Column Description headers
    $offset++;
    $worksheet->write($offset, 0, 'Column',$col_header);
    $worksheet->write($offset, 1, 'Size',  $col_header);
    $worksheet->write($offset, 2, 'Null', $col_header);
    $worksheet->write($offset, 3, 'Comment', $col_header);

    # Get column report for the table
    my $c_table;
    $c_table=get_table_col_report($dbh, $c_table, $owner, $table);
    my $tc_row_ref;
    while($tc_row_ref=$c_table->fetchrow_hashref()){
      $offset++;
      $worksheet->write($offset, 0, $tc_row_ref->{COLUMN_NAME});
      # Size column
      my $size = $tc_row_ref->{DATA_TYPE};
      # Precision
      if(defined $tc_row_ref->{DATA_PRECISION} && $tc_row_ref->{DATA_PRECISION}>0){
        if(defined $tc_row_ref->{DATA_SCALE} && $tc_row_ref->{DATA_SCALE}>0){
          $size.="($tc_row_ref->{DATA_PRECISION},$tc_row_ref->{DATA_SCALE})";
        }else{
          # Data scale is 0 - ignore
          $size.="($tc_row_ref->{DATA_PRECISION})";
        }
      }else{
        # Only show precision for non-binary and non-date
        if(!($tc_row_ref->{DATA_TYPE}=~/DATE|LOB|RAW|LONG|BFILE|ROWID|XML|TIMESTAMP/)){
          $size.="($tc_row_ref->{DATA_LENGTH})";
        }
      }
      $worksheet->write($offset, 1, $size);
      $worksheet->write($offset, 2, $tc_row_ref->{NULLABLE}=~/N/?'NO':'');
      $worksheet->write($offset, 3, $tc_row_ref->{COMMENTS});
    }

    # Show table partitions
    if($table_row_ref->{PARTITIONED} eq "YES"){
      my $c_partitions;
      $c_partitions=get_table_partitions($dbh, $c_partitions, $owner, $table);
      my $partition_row_ref;
      my $one_shot=0;
      while($partition_row_ref=$c_partitions->fetchrow_hashref()){
        if($one_shot==0){
          $one_shot=1;
          # Partitions headers
          $offset++;
          $worksheet->write($offset, 0, "Partition by $partition_row_ref->{PARTITIONING_TYPE}($partition_row_ref->{COLUMN_NAME})",$col_header);
          $worksheet->write($offset, 1, '',$col_header);
          $worksheet->write($offset, 2, '',$col_header);
          $worksheet->write($offset, 3, '',$col_header);
          $offset++;
          $worksheet->write($offset, 0, 'Name',       $col_header);
          $worksheet->write($offset, 1, 'Operation',  $col_header);
          $worksheet->write($offset, 2, 'Value',      $col_header);
          $worksheet->write($offset, 3, 'Tablespace', $col_header);
        }
        $offset++;
        my $partition_name=$partition_row_ref->{PARTITION_NAME};
        $worksheet->write($offset, 0, $partition_name);
        $worksheet->write($offset, 1, 'less than');
        # Get the high_value for the partition
        my $c_phv;
        $c_phv=get_partition_highvalues($dbh,$c_phv,$owner,$table,$partition_name);
        @row=$c_phv->fetchrow_array();
        $c_phv->finish();
        my $high_value = @row[0];
        if($high_value=~/TO_DATE/){
          $high_value=substr($high_value,9,17);
        }
        $worksheet->write($offset, 2, $high_value);
        # Get Tablespace, physical and storage attributes clause for partitions
        my $c_psc;
        $c_psc=get_partition_storage($dbh,$c_psc,$owner,$table,$partition_name);
        my $ps_row_ref=$c_psc->fetchrow_hashref();
        $c_psc->finish();
        # Tablespace clause
        if(defined $ps_row_ref->{TABLESPACE_NAME}){
          $worksheet->write($offset, 3, $ps_row_ref->{TABLESPACE_NAME});
        }else{
          # Use table's default tablespace clause
          if(defined $partition_row_ref->{DEF_TABLESPACE_NAME}){
            $worksheet->write($offset, 3, $partition_row_ref->{DEF_TABLESPACE_NAME}, $header);
          }
        }
      }
    }

    $workbook->close();

    # Split file into directory tree
    file2tree($file_name,$short_file_name);
  }
}

#----------------------------------------------------------------------------------#
# Script to text file
sub ScriptTextFile{
  # We now have a list of all the tables which to create CREATION scripts for:
  foreach (@schema_tables){
    my $owner=$_->{"schema"};
    my $object=$_->{"object"};
    # Get all details for the table
    my $c_table;
    $c_table=get_table_details($dbh, $c_table, $owner, $object);
    my $object_row_ref=$c_table->fetchrow_hashref();
    die "Failed to retrieve details of $owner.$object".(defined($dblink)?'@'.$dblink:'') if(!defined $object_row_ref->{OWNER});
    my $total_cols=0;

    # Make up file name
    my $short_file_name=lc($object).".sql";
    my $file_name = lc($owner).".tables.".$short_file_name;
    Oracle::Script::Common->info("Building creation script for table $owner.$object".(defined($dblink)?'@'.$dblink:'')." in file $short_file_name\n") if(!$quiet);
    open(F,"+>".$file_name) || die "Could not open temporary file $file_name for writing. $!\n";
    $file_count++;
    print F Oracle::Script::FileHeaders->MakeSQLFileHeader($file_name,$owner,$author,$dblink);
    print F "-- Table creation script for table $owner.$object\n--\n";
    print F Oracle::Script::FileHeaders->OracleDBDetails($userid,$password,$instance);
    print F "-- To run this script from the command line:\n";
    print F "-- sqlplus $owner/[password]\@[instance] \@$short_file_name\n";
    print F "------------------------------------------------------------------------------\n";
    print F "set feedback off;\n";
    print F "set serveroutput on size 1000000;\n";
    print F "prompt Creating table $owner.$object\n";
    print F "\n";
    print F "-- Drop table if it already exists\n";
    print F "-- Note that the contents of the table will also be deleted\n";
    print F "--  and that referential constraints will also be dropped.\n";
    print F "-- You will be warned when this happens.\n";
    print F "declare \n";
    print F "  v_count integer:=0;\n";
    print F "begin\n";
    print F "  select count(*)\n";
    print F "    into v_count\n";
    print F "    from sys.all_objects\n";
    print F "   where object_type = 'TABLE'\n";
    print F "     and owner = upper('".$owner."')\n";
    print F "     and object_name = upper('".$object."');\n";
    print F "  if(v_count>0)then\n";
    print F "    dbms_output.put_line('Table $owner.$object already exists. Dropping it');\n";
    print F "    execute immediate 'drop table $owner.$object';\n";
    print F "  end if;\n";
    print F "exception\n";
    print F "  when others then\n";
    print F "    if(v_count>0)then\n";
    print F "      dbms_output.put_line('and dropping referential constraints to it');\n";
    print F "      execute immediate 'drop table $owner.$object cascade constraints';\n";
    print F "    end if;\n";
    print F "end;\n";
    print F "/\n";

    # Begin creation script
    print F "------------------------------------------------------------------------------\n";
    print F "-- Create table\n";
    print F "------------------------------------------------------------------------------\n";

    if($object_row_ref->{TEMPORARY}=~/Y/){
      print F "create global temporary table $owner.$object\n(\n";
    }else{
      print F "create table $owner.$object\n(\n";
    }

    # Script columns
    # ~~~~~~~~~~~~~~
    my $c_columns;
    $c_columns=get_table_columns($dbh, $c_columns, $owner, $object);
    my $colum_row_ref;
    $one_shot=0;
    while($colum_row_ref=$c_columns->fetchrow_hashref()){
      $total_cols++;
      $sql=($one_shot==0)?'  ':', ';
      $one_shot=1;
      # Column name
      $sql.=sprintf('%-31s %-10s', $colum_row_ref->{COLUMN_NAME}, $colum_row_ref->{DATA_TYPE});
      print "  Column:        ($colum_row_ref->{COLUMN_NAME})\n" if($verbose);
      print "    +-Type:      ($colum_row_ref->{DATA_TYPE})\n" if($verbose);
      print "    +-Length:    ($colum_row_ref->{DATA_LENGTH})\n" if($verbose);
      print "    +-Precision: ($colum_row_ref->{DATA_PRECISION},$colum_row_ref->{DATA_SCALE})\n" if($debug);
      # Precision
      if(defined $colum_row_ref->{DATA_PRECISION} && $colum_row_ref->{DATA_PRECISION}>0){
        if(defined $colum_row_ref->{DATA_SCALE} && $colum_row_ref->{DATA_SCALE}>0){
          $sql.="($colum_row_ref->{DATA_PRECISION},$colum_row_ref->{DATA_SCALE})";
        }else{
          # Data scale is 0 - ignore
          $sql.="($colum_row_ref->{DATA_PRECISION})";
        }
      }else{
        # Only show precision for non-binary and non-date
        if(!($colum_row_ref->{DATA_TYPE}=~/DATE|LOB|RAW|LONG|BFILE|ROWID|XML/)){
          $sql.="($colum_row_ref->{DATA_LENGTH})";
        }
      }
      # Default column value
      my $long=$colum_row_ref->{DATA_DEFAULT};
      if(defined $long){$sql.=" default $long";}
      # Nullability
      if($colum_row_ref->{NULLABLE}=~/N/){$sql.=' not null';}
      # Column line complete
      print F "$sql\n";
    }
    print F ")\n";

    # Do table space, partitioning etc..
    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    if($object_row_ref->{TEMPORARY}=~/Y/){
      # Finish off temporary table
      # Note that we can not determine from the sys tables what type of commit
      # clause was used, so assume 'on commit delete rows', as this is the expected
      # behaviour of a temporary table.
      print F "on commit delete rows;";
    }else{
      # Tablespace clause
      if($object_row_ref->{TABLESPACE_NAME}){
        print F "tablespace \"$object_row_ref->{TABLESPACE_NAME}\"\n";
      }

      if(!$no_storage){
        # Physical attributes clause
        if($object_row_ref->{PCT_FREE}){
          print F "pctfree ".$object_row_ref->{PCT_FREE}."\n";
        }
        if($object_row_ref->{PCT_USED}){
          print F "pctused ".$object_row_ref->{PCT_USED}."\n";
        }
        if($object_row_ref->{INI_TRANS}){
          print F "initrans ".$object_row_ref->{INI_TRANS}."\n";
        }
        if($object_row_ref->{MAX_TRANS}){
          print F "maxtrans ".$object_row_ref->{MAX_TRANS}."\n";
        }

        # Table STORAGE clause
        if($object_row_ref->{INITIAL_EXTENT} ||
           $object_row_ref->{NEXT_EXTENT}    ||
           $object_row_ref->{MIN_EXTENTS}    ||
           $object_row_ref->{MAX_EXTENTS}    ||
           $object_row_ref->{PCT_INCREASE}) {
          print F "storage(\n";
          if($object_row_ref->{INITIAL_EXTENT}){
            print F "  initial ".($object_row_ref->{INITIAL_EXTENT}/1024)."K\n";
          }
          if($object_row_ref->{NEXT_EXTENT}){
            print F "  next ".($object_row_ref->{NEXT_EXTENT}/1024)."K\n";
          }
          if($object_row_ref->{MIN_EXTENTS}){
            print F "  minextents 1\n";
          }else{
            print F "  minextents ".$object_row_ref->{MIN_EXTENTS}."\n";
          }
          if($object_row_ref->{MAX_EXTENTS}==2147483645 || !defined $object_row_ref->{MAX_EXTENTS}){
            print F "  maxextents unlimited\n";
          }else{
            print F "  maxextents ".$object_row_ref->{MAX_EXTENTS}."\n";
          }
          if(!defined $object_row_ref->{PCT_INCREASE}){
            print F "  pctincrease 0\n";
          }else{
            print F "  pctincrease $object_row_ref->{PCT_INCREASE}\n";
          }
          print F ")\n";
        }
      }

      # Partitioning clauses
      # ~~~~~~~~~~~~~~~~~~~~
      if($object_row_ref->{PARTITIONED} eq 'YES'){
        # Script columns
        my $c_partitions;
        $c_partitions=get_table_partitions($dbh, $c_partitions, $owner, $object);
        my $partition_row_ref;
        my $one_shot=0;
        while($partition_row_ref=$c_partitions->fetchrow_hashref()){
          if($one_shot==0){
            $one_shot=1;
            print F "  partition by $partition_row_ref->{PARTITIONING_TYPE}($partition_row_ref->{COLUMN_NAME})(\n";
            $sql=   "    partition ";
          }else{
            $sql=   "  , partition ";
          }
          my $partition_name=$partition_row_ref->{PARTITION_NAME};
          # Get the high_value or list value for the partition
          my $c_phv;
          $c_phv=get_partition_highvalues($dbh,$c_phv,$owner,$object,$partition_name);
          @row=$c_phv->fetchrow_array();
          $c_phv->finish();
          my $high_value=@row[0]; # This can be a SQL string or a comma-delimited string of items

          if($partition_row_ref->{PARTITIONING_TYPE} eq 'LIST'){
            # List partition
            $sql.="'$partition_name' values ($high_value)\n";
          }elsif($partition_row_ref->{PARTITIONING_TYPE} eq 'RANGE'){
            # Range partition
            $sql.="'$partition_name' values less than ($high_value)\n";
          }else{
            # Hash partition
            $sql.="'$partition_name' \n";
          }
          print F  $sql;

          # Single-nested levels of sub-partitions
          if($partition_row_ref->{SUBPARTITION_TYPE} ne 'NONE'){
            my $c_subpartitions;
            $c_subpartitions=get_subpartition_details($dbh, $c_subpartitions, $owner, $object, $partition_name);
            my $subpartition_row_ref;
            my $one_shot=0;
            while($subpartition_row_ref=$c_subpartitions->fetchrow_hashref()){
              if($one_shot==0){
                $one_shot=1;
                print F "      subpartition by $partition_row_ref->{SUBPARTITIONING_TYPE}($partition_row_ref->{COLUMN_NAME})(\n";
                $sql=   "        partition ";
              }else{
                $sql=   "      , partition ";
              }
              if($partition_row_ref->{SUBPARTITION_TYPE} eq 'LIST'){
                # List sub-partition
                $sql.="'$subpartition_row_ref->{SUBPARTITION_NAME}' values ($subpartition_row_ref->{HIGH_VALUE})\n";
              }elsif($partition_row_ref->{SUBPARTITION_TYPE} eq 'RANGE'){
                # Range sub-partition
                $sql.="'$subpartition_row_ref->{SUBPARTITION_NAME}' values less than ($subpartition_row_ref->{HIGH_VALUE})\n";
              }else{
                # Hash sub-partition
                $sql.="'$subpartition_row_ref->{SUBPARTITION_NAME}' \n";
              }
              print F  $sql;
            }
            $c_subpartitions->finish();
            print F "      )\n";
          }


          # Get Tablespace, physical and storage attributes clause for partitions
          my $c_psc;
          $c_psc=get_partition_storage($dbh,$c_psc,$owner,$object,$partition_name);
          my $ps_row_ref=$c_psc->fetchrow_hashref();
          $c_psc->finish();
          # Tablespace clause
          if(defined $ps_row_ref->{TABLESPACE_NAME}){
            print F "      tablespace \"$ps_row_ref->{TABLESPACE_NAME}\"\n";
          }else{
            # Use table's tablespace clause
            if($partition_row_ref->{DEF_TABLESPACE_NAME}){
              print F "      tablespace \"$partition_row_ref->{DEF_TABLESPACE_NAME}\"\n";
            }
          }

          if(!$no_storage){
            # Physical attributes clause
            if(defined $ps_row_ref->{PCT_FREE}){
              print F "      pctfree  $ps_row_ref->{PCT_FREE}\n";
            }
            if(defined $ps_row_ref->{PCT_USED}){
              print F "      pctused  $ps_row_ref->{PCT_USED}\n";
            }
            if(defined $ps_row_ref->{INI_TRANS}){
              print F "      initrans $ps_row_ref->{INI_TRANS}\n";
            }
            if(defined $ps_row_ref->{MAX_TRANS}){
              print F "      maxtrans $ps_row_ref->{MAX_TRANS}\n";
            }

            # Storage attributes clause
            if(defined $ps_row_ref->{INITIAL_EXTENT} ||
               defined $ps_row_ref->{NEXT_EXTENT   } ||
               defined $ps_row_ref->{MIN_EXTENT    } ||
               defined $ps_row_ref->{MAX_EXTENT    } ||
               defined $ps_row_ref->{PCT_INCREASE  }) {
              print F "      storage \n";
              print F "      (\n";
              if($ps_row_ref->{INITIAL_EXTENT}){
                print F "        initial ".($ps_row_ref->{INITIAL_EXTENT}/1024)."K\n";
              }
              if($ps_row_ref->{NEXT_EXTENT}){
                print F "        next ".($ps_row_ref->{NEXT_EXTENT}/1024)."K\n";
              }
              if(!defined $ps_row_ref->{MIN_EXTENT}){
                print F "        minextents 1\n";
              }else{
                print F "        minextents $ps_row_ref->{MIN_EXTENT}\n";
              }
              if($ps_row_ref->{MAX_EXTENT}==2147483645 || !defined $ps_row_ref->{MAX_EXTENT}){
                print F "        maxextents unlimited\n";
              }else{
                print F "        maxextents $ps_row_ref->{MAX_EXTENT}\n";
              }
              if(!defined $ps_row_ref->{PCT_INCREASE}){
                print F "        pctincrease 0\n";
              }else{
                print F "        pctincrease $ps_row_ref->{PCT_INCREASE}\n";
              }
              if($ps_row_ref->{FREELISTS}==0 || !defined $ps_row_ref->{FREELISTS}){
                print F "        freelists 1\n";
              }else{
                print F "        freelists $ps_row_ref->{FREELISTS}\n";
              }
              if($ps_row_ref->{FREELIST_GROUPS}==0 || !defined $ps_row_ref->{FREELIST_GROUPS}){
                print F "        freelist groups 1\n";
              }else{
                print F "        freelist groups $ps_row_ref->{FREELIST_GROUPS}\n";
              }
              if(!defined $ps_row_ref->{BUFFER_POOL}){
                print F "        buffer pool default\n";
              }else{
                print F "        buffer pool $ps_row_ref->{BUFFER_POOL}\n";
              }
              print F "      )\n";
            }
          }
        }
        print F "  )\n";
      }

      if(!$no_storage){
        # Remaining Table configuration parameters:
        # Table Cache
        if($object_row_ref->{CACHE}=~/Y/){
          print F "  cache\n";
        }
        # Table Logging
        if(defined $object_row_ref->{LOGGING}){
          if($object_row_ref->{LOGGING}=~/YES/){
            print F "  logging\n";
          }else{
            print F "  nologging\n";
          }
        }
        # Table Degree of parallelism
        if(defined $object_row_ref->{DEGREE}){
          if($object_row_ref->{DEGREE}=~/0/){
            print F "  noparallel\n";
          }elsif($object_row_ref->{DEGREE}=~/1/){
            print F "  parallel\n";
          }else{
            print F "  parallel (\n";
            print F "    degree ".$object_row_ref->{DEGREE}=~s/^ //g."\n";
            print F "    instances ".$object_row_ref->{INSTANCES}=~s/^ //g."\n";
            print F "  )\n";
          }
        }
      }
      print F ";\n";
    }


    # Table Comments
    # ~~~~~~~~~~~~~~
    # Create the following SQL:
    # comment on table [SCHEMA].[TABLE] is
    #  '[Description]';
    my $c_tc;
    $c_tc=get_table_comments($dbh, $c_tc, $owner, $object);
    my $tc_row_ref = $c_tc->fetchrow_hashref();
    if($tc_row_ref->{COMMENTS}){
      print F " \n";
      print F "------------------------------------------------------------------------------\n";
      print F "-- Table comment:\n";
      print F "------------------------------------------------------------------------------\n";
      print F "comment on table $owner.$object is\n";
      print F "  '$tc_row_ref->{COMMENTS}';\n";
    }

    # Column Comments
    # ~~~~~~~~~~~~~~~
    # Create the following SQL:
    # comment on column [SCHEMA].[TABLE].[COLUMN] is
    #  '[Description]';
    # Reexecute cursor
    $c_columns->execute() || die "Error getting columns details of table $owner.$object.\n".$c_columns->errstr()."\n";
    $one_shot=0;
    my $col_row_ref;
    my $c_cc;
    while($col_row_ref=$c_columns->fetchrow_hashref()){
      $c_cc=get_column_comments($dbh, $c_cc, $owner, $object, $col_row_ref->{COLUMN_NAME});
      my $cc_row_ref=$c_cc->fetchrow_hashref();
      if($cc_row_ref->{COMMENTS}){
        if($one_shot==0){
          print F " \n";
          print F "------------------------------------------------------------------------------\n";
          print F "-- Column comments:\n";
          print F "------------------------------------------------------------------------------\n";
          $one_shot=1;
        }
        print F "comment on column $owner.$object.$col_row_ref->{COLUMN_NAME} is\n";
        print F "  '$cc_row_ref->{COMMENTS}';\n";
      }
    }

    # All constraints
    # ~~~~~~~~~~~~~~~
    my $last_constraint = 'fish';
    my $c_constraints;
    $c_constraints=get_table_constraints($dbh, $c_constraints, $owner, $object);
    my $ccon_row_ref;
    while($ccon_row_ref=$c_constraints->fetchrow_hashref()){

      # Print section heading
      if($last_constraint ne $ccon_row_ref->{CONSTRAINT_TYPE}){
        $last_constraint=$ccon_row_ref->{CONSTRAINT_TYPE};
        print F " \n";
        print F "------------------------------------------------------------------------------\n";
        if($ccon_row_ref->{CONSTRAINT_TYPE}=~/P/){
          print F "-- Create/Recreate primary key constraints\n";
        }elsif($ccon_row_ref->{CONSTRAINT_TYPE}=~/U/){
          print F "-- Create/Recreate unique key constraints\n";
        }elsif($ccon_row_ref->{CONSTRAINT_TYPE}=~/C/){
          print F "-- Create/Recreate check constraints\n";
        }elsif($ccon_row_ref->{CONSTRAINT_TYPE}=~/R/){
          print F "-- Create/Recreate foreign constraints\n";
        }
        print F "------------------------------------------------------------------------------\n";
      }

      print F "alter table $owner.$object\n";
      # (Note: Do not include the schema in the constraint name)
      print F "  add constraint $ccon_row_ref->{CONSTRAINT_NAME}\n";
      if($ccon_row_ref->{CONSTRAINT_TYPE}=~/P/){
        $sql="  primary key (";
      }elsif($ccon_row_ref->{CONSTRAINT_TYPE}=~/U/){
        $sql="  unique (";
      }elsif($ccon_row_ref->{CONSTRAINT_TYPE}=~/C/){
        $sql="  check (";
      }elsif($ccon_row_ref->{CONSTRAINT_TYPE}=~/R/){
        $sql="  foreign key (";
      }else{
        die "Unknown constraint type\n";
      }

      # Get constraint columns
      if($ccon_row_ref->{CONSTRAINT_TYPE}=~/C/){
        # Get Check constraint columns
        # Special case for check constraint - all the columns
        # are already in the LONG-type search_condition column
        my $long = $ccon_row_ref->{search_condition};
        $sql.=$long;
      }else{
        # Get Primary and Foreign Unique constraint columns
        my $c_cons_columns;
        $c_cons_columns=get_column_constraints($dbh, $c_cons_columns, $owner, $object, $ccon_row_ref->{CONSTRAINT_NAME});
        my $ccon_row_ref;
        $one_shot=0;
        while($ccon_row_ref=$c_cons_columns->fetchrow_hashref()){
          $sql.=($one_shot==0)?'':',';
          $one_shot=1;
          $sql.=$ccon_row_ref->{COLUMN_NAME};
        }
      }
      print F  "$sql)\n";

      # Specfy which indexes to use for primary and unique constrains
      if($ccon_row_ref->{CONSTRAINT_TYPE}=~/P|U/){
        print F "  using index\n";
      }

      # Specify which tables reference foreign constraint
      if($ccon_row_ref->{CONSTRAINT_TYPE}=~/R/){
        # Get foreign Table details
        # There can be only one such foreign table for this constraint
        my $c_foreign_table;
        $c_foreign_table=get_remote_constraint_table_key_name($dbh, $c_foreign_table,$ccon_row_ref->{CONSTRAINT_NAME});
        my $foreign_table_row_ref;
        if($foreign_table_row_ref=$c_foreign_table->fetchrow_hashref()){
          my $r_constraint_name=$foreign_table_row_ref->{R_CONSTRAINT_NAME};
          # Get table and column details for this remote contraint name
          my $c_cons_columns;
          $c_cons_columns=get_referenced_key_column($dbh, $c_cons_columns, $r_constraint_name);
          my $ccon_row_ref;
          $one_shot=0;
          $sql="  references ";
          while($ccon_row_ref=$c_cons_columns->fetchrow_hashref()){
            if($one_shot==0){
              # First column in referenced key
              $sql.="$ccon_row_ref->{OWNER}.$ccon_row_ref->{TABLE_NAME}($ccon_row_ref->{COLUMN_NAME}";
              $one_shot=1;
            }else{
              # List further columns
              $sql.=",$ccon_row_ref->{COLUMN_NAME}";
            }
          }
          print F  "$sql)\n";
        }
      }

      # PRIMARY or UNIQUE CONSTRAINTS
      if($ccon_row_ref->{CONSTRAINT_TYPE}=~/P|U/){
        if($object_row_ref->{PARTITIONED}=~/YES/){
          # Partitinioned index
          print F "  local\n";
          print F "  (\n";
          my $c_partitions;
          $c_partitions=get_table_partitions($dbh, $c_partitions, $owner, $object);
          my $partition_row_ref;
          my $one_shot=0;
          while($partition_row_ref=$c_partitions->fetchrow_hashref()){
            $sql=($one_shot==0)?'  ':', ';
            $one_shot=1;
            $sql.="  partition $partition_row_ref->{PARTITION_NAME} tablespace '$partition_row_ref->{DEF_TABLESPACE_NAME}'";
            print F  "$sql\n";
          }
          print F  "  )\n";
          if(!$no_storage){
            # Percent Free
            print F "  pctfree  $object_row_ref->{PCT_FREE}\n";
            # The minimum and default INITRANS value for a cluster or index is 2.
            my $initrans=$object_row_ref->{INI_TRANS};
            if($initrans==1){
              $initrans=2;
            }
            print F "  initrans $initrans\n";
            print F "  maxtrans $object_row_ref->{MAX_TRANS}\n";
          }
        }else{
          # Non-Partitinioned index
          # Get the tablespace name for this index
          my $c_index_tablespace=$dbh->prepare(
            "select tablespace_name ".
            "  from sys.all_indexes ".
            " where owner = ".$dbh->quote($owner).
            "   and table_name=".$dbh->quote($object).
            "   and index_name=".$dbh->quote($ccon_row_ref->{CONSTRAINT_NAME}));
          $c_index_tablespace->execute() || die "Error getting tablespace name for an index on table $owner.$object".(defined($dblink)?'@'.$dblink:'')."\n".$c_index_tablespace->errstr()."\n";
          my $c_index_tablespace_row_ref=$c_index_tablespace->fetchrow_hashref();
          if(length($c_index_tablespace_row_ref->{TABLESPACE_NAME})==0){
            # Could not get tablespace name for contraint - use that of the table as a last resort
            print F "  tablespace \"$object_row_ref->{TABLESPACE_NAME}\"\n";
          }else{
            print F "  tablespace \"$c_index_tablespace_row_ref->{TABLESPACE_NAME}\"\n";
          }
          $c_index_tablespace->finish();

          if(!$no_storage){
            # Percent Free
            print F "  pctfree  $object_row_ref->{PCT_FREE}\n";
            # The minimum and default INITRANS value for a cluster or index is 2.
            my $initrans=$object_row_ref->{INI_TRANS};
            if($initrans==1){
              $initrans=2;
            }
            print F "  initrans $initrans\n";
            print F "  maxtrans $object_row_ref->{MAX_TRANS}\n";
          }
        }
        if(!$no_storage){
          if(defined $object_row_ref->{INITIAL_EXTENT} ||
             defined $object_row_ref->{NEXT_EXTENT} ||
             defined $object_row_ref->{MIN_EXTENTS} ||
             defined $object_row_ref->{MAX_EXTENTS} ||
             defined $object_row_ref->{PCT_INCREASE}) {
            print F "  storage \n";
            print F "  (\n";
            if($object_row_ref->{INITIAL_EXTENT}){
              print F "    initial ".($object_row_ref->{INITIAL_EXTENT}/1024)."K\n";
            }
            if($object_row_ref->{NEXT_EXTENT}){
              print F "    next ".($object_row_ref->{NEXT_EXTENT}/1024)."K\n";
            }
            if(!defined $object_row_ref->{MIN_EXTENTS}){
              print F "    minextents 1\n";
            }else{
              print F "    minextents $object_row_ref->{MIN_EXTENTS}\n";
            }
            if($object_row_ref->{MAX_EXTENTS}==2147483645 || !defined $object_row_ref->{MAX_EXTENTS}){
              print F "    maxextents unlimited\n";
            }else{
              print F "    maxextents $object_row_ref->{MAX_EXTENTS}\n";
            }
            if(!defined $object_row_ref->{PCT_INCREASE}){
              print F "    pctincrease 0\n";
            }else{
              print F "    pctincrease $object_row_ref->{PCT_INCREASE}\n";
            }
            print F "  )\n";
          }
        }
        print F ";\n";
      }elsif($ccon_row_ref->{CONSTRAINT_TYPE}=~/R/){
        print F ";\n";
      }else{
        print F "  $ccon_row_ref->{STATUS};\n";
      }

    }

    # Indexes
    # ~~~~~~~
    # Outline statement:
    #  create [unique] index [index_owner].[index_name] on [table_owner].[table_name]([col1,col2..])
    #        tablespace "[tablespace_name]"
    #        pctfree  [x]
    #        initrans [y]
    #        maxtrans [z]
    #        storage
    #        (
    #          initial [a]K
    #          minextents [b]
    #          maxextents unlimited
    #          pctincrease [c]
    #        )
    #    parallel
    #    logging
    #  ;
    $one_shot=0;
    my $c_table_indexes;
    $c_table_indexes=get_table_indexes($dbh,$c_table_indexes,$owner,$object);
    my $ti_row_ref;
    while($ti_row_ref=$c_table_indexes->fetchrow_hashref()){
      if($one_shot==0){
        $one_shot=1;
        print F " \n";
        print F "------------------------------------------------------------------------------\n";
        print F "-- Create/Recreate indexes \n";
        print F "------------------------------------------------------------------------------\n";
      }
      $sql="create ";
      if($ti_row_ref->{UNIQUENESS} eq "UNIQUE"){
        $sql.="unique ";
      }
      if($ti_row_ref->{INDEX_TYPE} ne "NORMAL"){
        $sql.=$ti_row_ref->{INDEX_TYPE}=~s/^ +//." ";
      }
      $sql.="index $ti_row_ref->{OWNER}.$ti_row_ref->{INDEX_NAME} on $ti_row_ref->{TABLE_OWNER}.$ti_row_ref->{TABLE_NAME}(";
      # Get index columns
      # e.g. create index SCOTT.IX_EMP_ADDRESS on SCOTT.EMP(ADDRESS)
      $two_shot=0;
      my $c_index_cols;
      $c_index_cols=get_index_columns($dbh,$c_index_cols,$owner,$object,$ti_row_ref->{INDEX_NAME});
      my $ic_row_ref;
      while($ic_row_ref=$c_index_cols->fetchrow_hashref()){
        if($two_shot==0){
          $two_shot=1;
        }else{
          $sql.=',';
        }
        $sql.=$ic_row_ref->{COLUMN_NAME};
      }
      print F  "$sql)\n";

      # Tablespace clause
      if($ti_row_ref->{TABLESPACE_NAME}){
        print F "  tablespace \"$ti_row_ref->{TABLESPACE_NAME}\"\n";
      }
      if(!$no_storage){
        # Physical attributes clause
        if($ti_row_ref->{PCT_FREE}){
          print F "  pctfree  $ti_row_ref->{PCT_FREE}\n";
        }
        if($ti_row_ref->{INI_TRANS}){
          print F "  initrans $ti_row_ref->{INI_TRANS}\n";
        }
        if($ti_row_ref->{MAX_TRANS}){
          print F "  maxtrans $ti_row_ref->{MAX_TRANS}\n";
        }

        # Index Storage attributes clause
        if($ti_row_ref->{INITIAL_EXTENT} ||
           $ti_row_ref->{NEXT_EXTENT   } ||
           $ti_row_ref->{MIN_EXTENTS   } ||
           $ti_row_ref->{MAX_EXTENTS   } ||
           $ti_row_ref->{PCT_INCREASE  }) {
          print F "  storage \n";
          print F "  (\n";
          if($ti_row_ref->{INITIAL_EXTENT}){
            print F "    initial ".($ti_row_ref->{INITIAL_EXTENT}/1024)."K\n";
          }
          if($ti_row_ref->{NEXT_EXTENT}){
            print F "    next ".($ti_row_ref->{NEXT_EXTENT}/1024)."K\n";
          }
          if(defined $ti_row_ref->{MIN_EXTENTS}){
            print F "    minextents 1\n";
          }else{
            print F "    minextents $ti_row_ref->{MIN_EXTENTS}\n";
          }
          if($ti_row_ref->{MAX_EXTENTS}==2147483645 || !defined $ti_row_ref->{MAX_EXTENTS}){
            print F "    maxextents unlimited\n";
          }else{
            print F "    maxextents $ti_row_ref->{MAX_EXTENTS}\n";
          }
          if(!defined $ti_row_ref->{PCT_INCREASE}){
            print F "    pctincrease 0\n";
          }else{
            print F "    pctincrease $ti_row_ref->{PCT_INCREASE}\n";
          }
          print F   "  )\n";
        }
      }

      # Index on partitioned table=head3 File format

      if($object_row_ref->{PARTITIONED} eq "YES"){
        # Partitioned index
        print F "  local\n";
        print F "  (\n";
        $one_shot=0;
        my $c_indexes_part;
        $c_indexes_part=get_index_partitions($dbh,$c_indexes_part,$ti_row_ref->{INDEX_NAME});
        my $ip_row_ref;
        while($ip_row_ref=$c_indexes_part->fetchrow_hashref()){
          $sql=($one_shot==0)?'    ':'  , ';
          $one_shot=1;
          $sql.="partition $ip_row_ref->{PARTITION_NAME} tablespace \"$ip_row_ref->{TABLESPACE_NAME}\"";
          if(!$no_storage){
            # Index Partition Logging clause
            if(defined $ip_row_ref->{LOGGING}){
              if($object_row_ref->{LOGGING}=~/YES/){
                $sql.=' logging';
              }else{
                $sql.=' nologging';
              }
            }
          }
          print F  "$sql\n";

          # Single-nested levels of sub-partitions
          if($ip_row_ref->{COMPOSITE} eq 'YES'){
            print "    (\n";
            my $c_subpartitions;
            $c_subpartitions=get_subpartition_details($dbh, $c_subpartitions, $ip_row_ref->{INDEX_OWNER}, $ip_row_ref->{INDEX_NAME}, $ip_row_ref->{PARTITION_NAME});
            my $subpartition_row_ref;
            my $one_shot=0;
            while($subpartition_row_ref=$c_subpartitions->fetchrow_hashref()){
              $sql=($one_shot==0)?'      ':'    , ';
              $one_shot=1;
              $sql.="partition $subpartition_row_ref->{SUBPARTITION_NAME}";
              print F  "$sql\n";
            }
            $c_subpartitions->finish();
            print F "      )\n";
          }
          #---------------------------
        }
        print F "  )\n";
      }

      if(!$no_storage){
        # Index Parallel clause -- add instance parameter in here as well
        if($object_row_ref->{DEGREE}=~/0/){
          print F "  noparallel\n";
        }elsif($object_row_ref->{DEGREE}=~/1/){
          print F "  parallel\n";
        }else{
          print F "  parallel (\n";
          print F "    degree ".$object_row_ref->{DEGREE}=~s/^ +//."\n";
          print F "    instances ".$object_row_ref->{INSTANCES}=~s/^ +//."\n";
          print F "  )\n";
        }
        # Index Logging clause
        if(defined $object_row_ref->{LOGGING}){
          if($object_row_ref->{LOGGING}=~/YES/){
            print F "  logging\n";
          }else{
            print F "  nologging\n";
          }
        }
      }
      print F ";\n";
    }

    # Table Priviledges
    # ~~~~~~~~~~~~~~~~~
    # Only include them if explicitly required - there is another scripts that will centrally create all grants
    if($grants){
      $one_shot=0;
      my $c_grantees;
      $c_grantees=get_table_grantees($dbh,$c_grantees,$owner,$object);
      my $tg_row_ref;
      while($tg_row_ref=$c_grantees->fetchrow_hashref()){
        if($one_shot==0){
          $one_shot=1;
          print F " \n";
          print F "------------------------------------------------------------------------------\n";
          print F "-- Grant/Revoke privileges\n";
          print F "------------------------------------------------------------------------------\n";
        }
        if($tg_row_ref->{GRANT_COUNT}>=7){
          # Full house: we can say "grant all"
          $sql="grant all";
        }else{
          # Show selection of grant for this grantee
          $two_shot=0;
          $sql="grant ";
          my $c_grants;
          $c_grants=get_table_grants($dbh,$c_grants,$owner,$object,$tg_row_ref->{GRANTEE});
          my $tgr_row_ref;
          while($tgr_row_ref=$c_grants->fetchrow_hashref()){
            if($two_shot==0){
              $two_shot=1;
            }else{
              $sql.=', ';
            }
            $sql.=$tgr_row_ref->{PRIVILEGE};
          }
        }
        $sql.=" on $owner.$object to $tg_row_ref->{GRANTEE};\n";
        print F $sql;
      }
    }

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
    Oracle::Script::Common->info("Table $owner.$object has $total_cols columns.\n") if $verbose;

    # Split file into directory tree
    Oracle::Script::Common->file2tree($file_name);
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
# Get all individually specified tables
if($meta_tables){
  my @spec_tables=split(/,/,$meta_tables);
  foreach my $object(@spec_tables){
    my @schema_table=split(/\./,$object);
    # Where no schema name is defined, default to the user login schema
    if(!exists $schema_table[1]){
      push(@schema_table,@schema_table[0]);
      @schema_table[0]=$userid;
    }
    print "Individually specified table: ",uc(@schema_table[0].@schema_table[1]),"\n" if($verbose);
    # Check if this table exists
    my $cursor;
    $cursor=does_table_exist($dbh,$cursor,@schema_table[0],@schema_table[1]);
    # Fetch single record
    @row=$cursor->fetchrow_array();
    if(scalar(@row)==0){
      die "Individually specified table ",uc(@schema_table[0].@schema_table[1])," does not exist or should not scripted.\n";
    }else{
      push(@schema_tables,{"schema"=>uc(@schema_table[0]),"object"=>uc(@schema_table[1])});
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
  $cursor=get_scriptable_tables($dbh,$cursor,$meta_schemas);
  my $objects_ref = $cursor->fetchall_arrayref();
  foreach my $row(@{$objects_ref}){
    my ($schema,$object) = @{$row};
    print "Table specified by schema: $schema.$object\n" if($verbose);
    push(@schema_tables,{"schema"=>$schema,"object"=>$object});
  }
  $cursor->finish();
}

# Default, if no schemas or tables have been defined
if(!$meta_tables && !$meta_schemas){
  print "Creating table initialisation scripts for all tables in schema $userid.\n" if($verbose);
  # Get all the tables that belong to the schemas
  my $cursor;
  $cursor=get_scriptable_tables($dbh,$cursor,$userid);
  my $objects_ref = $cursor->fetchall_arrayref();
  foreach my $row(@{$objects_ref}){
    my ($schema,$object) = @{$row};
    print "Table specified by schema: $schema.$object\n" if($verbose);
    push(@schema_tables,{"schema"=>$schema,"object"=>$object});
  }
  $cursor->finish();
}

# Remove duplicate items from @schema_tables
my $last;
my @schema_tables_;
foreach (sort {$a->{"schema"}.".".$a->{"object"} <=> $b->{"schema"}.".".$b->{"object"}} @schema_tables){
  if($last ne $_->{"schema"}.".".$_->{"object"}){
    push(@schema_tables_,{"schema"=>$_->{"schema"},"object"=>$_->{"object"}});
  }
  $last=$_->{"schema"}.".".$_->{"object"};
}
@schema_tables=@schema_tables_;

if($excel){
  ScriptSpreadsheet;
}else{
  ScriptTextFile;
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

ScriptTables.pl - Generates formal creation scripts for tables

=head1 SYNOPSIS

=over 4

=item B<ScriptTables.pl> B<-i> db1 B<-u> user B<-p> passwd

Builds the creation scripts for all the tables in the schema 'user' on
database instance db1.

=item B<ScriptTables.pl> B<-i> db1 B<-u> user B<-p> passswd B<-m> schema1 B<-m> schema2

Builds the creation scripts only for all the tables in the schemas 'schema1'
and 'schema2' on database instance db1. Use this form if the required schema
does not have select rights to SYS.ALL_... views, and use a system user to log
with.

=item B<ScriptTables.pl> B<-i> db1 B<-u> user B<-p> passwd B<-t> schema1.table1

Builds the creation scripts only for the table 'schema1.table1' on database
instance db1.

=item B<ScriptTables.pl> B<-i> db1 B<-u> user B<-p> passwd -l db2

Builds the creation scripts for all the tables in the DBLink's default schemas
of the remote database instance, which is accessed from this database instance
db1 via database link db2.

=item B<ScriptTables.pl> B<-i> db1 B<-u> user B<-p> passwd B<-m> schema1,schema2 B<-l> db2

Builds the creation scripts for all the tables in the schemas 'schema1'
and 'schema2' on a remote database instance that is accessed from this
Oracle instance db1 via the database link db2.

=item B<ScriptTables.pl> B<--help>

Provides detailed description.

=back

=head1 OPTIONS AND ARGUMENTS

B<ScriptTables.pl> B<-u|--user> UserId B<-p|--password> Passwd [B<-i|--instance> Instance name]
[-l|--dblink DBLink] [-s|--schemas Schemas] [-o|--objects Tables] [--no-storage]
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

B<2.> Temporary tables are assumed to be global. This is not always the case.

B<3.> Table spaces are implemented exactly as they are
used on the source database. The tables space names will not necessarily have
the same name on the target database that this script is subsequently run on.
One way around this is to substitute the tablespace names with SQL "defines",
which need to be specified when running the resulting SQL script.

B<4.> Make date format consistent.

B<5.> Complete testing of table and index sub-partitions

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

