#!/usr/bin/perl
#----------------------------------------------------------------------------------#
#----------------------------------------------------------------------------------#
# FUNCTION:
# Creates decorative file headers for a number of programming languages
#----------------------------------------------------------------------------------#
# Copyright (c) 1999-2004 Gerrit Hoekstra
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
#  USAGE:
#  This package creates file headers and footers for automatically-generated
#  source code files, of the programming languages C++, SQL, Perl, Unix Shell and
#  Windows batch file.
#
#  This package is used to generate files that will comply with your particular corporate
#  standards, for which the contents of the headers if fully configurable.
#
#  Currently, the file headers represent a best practise format, which includes an
#  optional commecial copyright notice commonly used by UK companies if you specify
#  your name or the name of the your company. You can also display the GPL license
#  instead of the commercial license.
#
#  The self-expanding Source Control System strings are currently only for
#  MS's Visual Source Safe and MKS.
#
#  When a SQL file is generated from an Oracle database, some heplful information
#  about the database can be extracted. For this to work, you need to
#  supply the login details and have DBD::Oracle and DBI installed.
#
#----------------------------------------------------------------------------------
#  INSTALLATION:
#  Put this package somewhere in your perl @INC path.
#  To see your perl @INC path from the command line:
#  perl -e 'print join(qq|\n|,@INC),"\n"';
#----------------------------------------------------------------------------------
package Oracle::Script::FileHeaders;

use strict;
use POSIX qw/strftime/;
use Time::Local;
use File::Path;
use File::Copy;
use File::Compare;
use File::Basename;
use Time::localtime;
use File::Temp qw/tempfile tempdir/;

our $VERSION = '0.01';

# ================================================================================#
# Public data
# ================================================================================#
my $CompanyName;
my $Author;
my $CheckInComment = 'Automatic Builder';   # Global Checkin comment
my $GPL = 0;

#----------------------------------------------------------------------##
# Description: initialise this object after compilation
#   Arguments: none
#     Returns: none
#----------------------------------------------------------------------##
sub INIT{
    my $proto='FileHeaders';
    my $class=ref($proto)||$proto;  # Make reference to this package name
    my $self={};                    # reference to hash of this package
    bless($self, $class);           # make this
    return $self;
}

##############################################################################################################
#   Function:   Sets the global check-in Comment
#               This comment will be used for all subsequent check-ins
#   Parameters: The check-in comment
sub SetCheckInComment{
    $CheckInComment = shift;
}

##############################################################################################################
#   Function:   Sets the company name - this will cause a commercial proprietory copyright notice to be
#               included at the top of every file, unless the GPL option has been specified, in which case
#               a GPL licence will be dipslayed.
#   Parameters: Company name
sub SetCompanyName{
    $CompanyName = shift;
}

##############################################################################################################
#   Function:   Sets the author's name if it is not going to be obvious from the
#               Source Control file header.
#   Parameters: Author Name
sub SetAuthorName{
    $Author = shift;
}

##############################################################################################################
#   Function:   Causes the GPL licence to be included in each file header
sub SetGPLLicense{
    $GPL = 1;
}

#-----------------------------------------------------------------------------
# Create basic file header with source control strings and Copyright notice
# Amend Copyright notice here
# Parameters:   1. Comment line preable. For C++='//' (specified as '\/\/'),
#                  for SQL='--', for Perl and Unix shell scripts: '#'.
#               2. Company Name for copyright notice. Specify your own name or that of the
#                  company that wants to retain commercial copyright (Yeuch! See parameter 4.)
#                  If no name or a null is specified, no commectial copyright notice
#                  will be shown.
#               3. Author name or email address.
#               4. GPL License instead of the commercial license. This will be displayed
#                  instead of the commecial license if the Company name in parameter 2
#                  has been specified.
# TODO:
# Hash parameters for types of version control header, license, author, company name
sub BasicFileHeader{
  my ($preamble,$CompanyName,$Author,$GPL)=@_;
  my $Year = localtime->year() + 1900;
  my $Header;
  $Header.="$preamble----------------------------------------------------------------------------\n";
  $Header.="$preamble ".ExpHeader()."\n";
  # Specific to VSS
  # $Header.="$preamble  File name:                    ".ExpWorkFile()."\n";
  # $Header.="$preamble  Source Control Version:       ".ExpRevision()."\n";
  # $Header.="$preamble  Last checked in on:           ".ExpDate()."\n";
  # $Header.="$preamble  Last modified by:             ".ExpAuthor()."\n";
  # $Header.="$preamble  Repository file location:     ".ExpArchive()."\n";
  $Header.="$preamble----------------------------------------------------------------------------\n";
  if(defined $CompanyName){
    $Header.="$preamble  (c) Copyright $Year $CompanyName.  All rights reserved.\n";
    $Header.="$preamble  \n";
    if(!defined $GPL){
      # Common European and USA statement of selfishness:
      $Header.="$preamble  These coded instructions, statements and computer programs contain\n";
      $Header.="$preamble  unpublished information proprietary to $CompanyName and are protected\n";
      $Header.="$preamble  by international copyright law. They may not be disclosed to third\n";
      $Header.="$preamble  parties, copied or duplicated, in whole or in part, without the prior\n";
      $Header.="$preamble  written consent of $CompanyName.\n";
      $Header.="$preamble  \n";
    }
  }
  if(defined $GPL){
    $Header.="$preamble  This program is free software; you can redistribute it and/or\n";
    $Header.="$preamble  modify it under the terms of the GNU General Public License\n";
    $Header.="$preamble  as published by the Free Software Foundation; either version 2\n";
    $Header.="$preamble  of the License, or (at your option) any later version.\n";
    $Header.="$preamble  \n";
    $Header.="$preamble  This program is distributed in the hope that it will be useful,\n";
    $Header.="$preamble  but WITHOUT ANY WARRANTY; without even the implied warranty of\n";
    $Header.="$preamble  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the\n";
    $Header.="$preamble  GNU General Public License for more details. <www.gnu.org>\n";
    $Header.="$preamble  \n";
  }
  if(defined $Author){
    $Header.="$preamble  \n";
    $Header.="$preamble  Author: $Author\n";
    $Header.="$preamble  \n";
  }
# $Header.="$preamble----------------------------------------------------------------------------\n";
# $Header.="$preamble  \n";
# $Header.="$preamble----------------------------------------------------------------------------\n";
  return $Header;
}

#----------------------------------------------------------------------
# Version Control System self-expanding strings
# This is done like this so that the version control system will not
# actually expand these string definitions when this file is checked in.
#
sub ExpHeader{
    return '$'.'Header: '.'$';
}
sub ExpWorkFile{
    return '$'.'Workfile: '.'$';
}
sub ExpRevision{
    return '$'.'Revision: '.'$';
}
sub ExpDate{
    return '$'.'Date: '.'$';
}
sub ExpAuthor{
    return '$'.'Author: '.'$';
}
sub ExpArchive{
    return '$'.'Archive: '.'$';
}
sub ExpHistory{
    return '$'.'History: '.'$';
}

# Function:   Get the Oracle database details into a string for inserting into the
#             file header.
# Parameters: 1. User Id
#             2. Password
#             3. Oracle Instance name
#             4. Line Comment identifier. Defaults to '--'
#             5. Database Link name
sub OracleDBDetails{
  my $self=shift;
  my $userid=shift;
  my $password=shift;
  my $instance=shift;
  my $comm=shift||'--';
  my $dblink=shift;


  # Use eval here, as not all users of this package will use this function and have DBI installed.
  my $spiel;
  eval{
    use DBI;
    use DBD::Oracle qw(:ora_session_modes);
    my $mode=0;
    $mode=ORA_SYSDBA if($userid=~m/sys /i);
    my $dbh = DBI->connect("dbi:Oracle:$instance", $userid, $password,{ora_session_mode=>$mode})
      || die "Unable to connect to $instance: $DBI::errstr\n";

    # Get all the details about the database.
    # Currently, it is specific to an Oracle database. Will DBI support a generic interface?
    # Get IP Address:
    my $sth=$dbh->prepare(
      "select rtrim(sys_context('userenv','ip_address')) from dual".(defined($dblink)?'\@'.$dblink:''));
    $sth->execute;
    my @row=$sth->fetchrow_array;
    my $ip_address=@row[0];
    $sth->finish();

    # Get fully qualified instance name:File System
    # Note that this not necessarily the same instance name which you logged on with
    my $sth=$dbh->prepare(
      "select rtrim(sys_context('userenv','db_name')) from dual".(defined($dblink)?'\@'.$dblink:''));
    $sth->execute;
    @row=$sth->fetchrow_array;
    my $instance_name=@row[0];
    $sth->finish();

    my $sth=$dbh->prepare(
      "select rtrim(sys_context('userenv','db_domain')) from dual".(defined($dblink)?'\@'.$dblink:''));
    $sth->execute;
    @row=$sth->fetchrow_array;
    $instance_name.=@row[0];
    $sth->finish();

    # Get Fully qualfied user name
    my $sth=$dbh->prepare(
      "select rtrim(sys_context('userenv','os_user')) from dual".(defined($dblink)?'\@'.$dblink:''));
    $sth->execute;
    @row=$sth->fetchrow_array;
    my $user_name=@row[0];
    $sth->finish();

    # Get Terminal Name
    my $sth=$dbh->prepare(
      "select rtrim(sys_context('userenv','terminal')) from dual".(defined($dblink)?'\@'.$dblink:''));
    $sth->execute;
    @row=$sth->fetchrow_array;
    my $terminal=@row[0];
    $sth->finish();

    # Get Client Name which this script is run from
    my $sth=$dbh->prepare(
      "select replace(rtrim(sys_context('userenv','host')),chr(0),'') from dual".(defined($dblink)?'\@'.$dblink:''));
    $sth->execute;
    @row=$sth->fetchrow_array;
    my $client=@row[0];
    $sth->finish();

    # Get Current time on the database
    my $sth=$dbh->prepare(
      "select to_char(sysdate,'DDMONYYYY HH24:MI:SS') from dual".(defined($dblink)?'\@'.$dblink:''));
    $sth->execute;
    @row=$sth->fetchrow_array;
    my $db_time=@row[0];
    $sth->finish();

    # Get Language set on the database
    my $sth=$dbh->prepare(
      "select rtrim(sys_context('userenv','language')) from dual".(defined($dblink)?'\@'.$dblink:''));
    $sth->execute;
    @row=$sth->fetchrow_array;
    my $language=@row[0];
    $sth->finish();

    $dbh->disconnect;

    $spiel = (defined($dblink)
      ? "$comm This file was generated from the remote database instance $instance_name\@$dblink.\n"
      : "$comm This file was generated from database instance $instance_name.\n" );
    $spiel.="$comm   Database Time    : $db_time\n".
            "$comm   IP address       : $ip_address\n".
            "$comm   Database Language: $language\n".
            "$comm   Client Machine   : $client\n".
            "$comm   O/S user         : $user_name\n";
  };
  $spiel="$comm Could not get database details.\n" if $@;
  return $spiel;
}

##############################################################################################################
#   Function:   Generates a temporary file name and opens the file in the OS's standard temporary directory.
#               The temporary file is closed and deleted when the calling program exits.
#               Returns the file handle to the file
sub MakeTempFile
{
  my $self=shift;
  my $dir=File::Spec->tmpdir();
  my ($filehandle,$filename)=File::Temp->tempfile(DIR=>$dir,SUFFIX=>'.tmp',UNLINK=>1);
  return $filehandle;
}

##############################################################################################################
# Makes up the file guard for CPP header files
#   Parameters:
#   Returns:    File guard, in the form: _FILE_NAME_H_
sub MakeCPPHeaderFileGuard
{
    $_ = shift;
    tr/a-z/A-Z/;
    s/\./_/;
    s/ /_/;
    my $Guard = '_'.$_.'_';
    return $Guard;
}

##############################################################################################################
#   Function:   Makes a CPP File header for a file
#   Parameters: 1. File Name
#               2. Company Name for copyright notice
#               3. Author name
#   Returns:    Complete file header
sub MakeCPPFileHeader
{
    my $self        = shift;
    my $FileName    = shift;
    my $CompanyName = shift||$CompanyName;
    my $Author      = shift||$Author;
    # Check if it is a CPP header file from the name of the file
    my $IsHeader =~ /.+\.h$|.+\.hpp$|.+\.hxx$/i;
    my $Header=BasicFileHeader('\/\/',$CompanyName,$Author,$GPL);
    if($IsHeader){
        my $Guard = MakeCPPHeaderFileGuard($FileName);
        $Header.="#pragma once\n";
        $Header.="\n";
        $Header.="#ifndef $Guard\n";
        $Header.="#define $Guard\n";
        $Header.="\n";
        $Header.='#pragma message("Including " __FILE__)'."\n";
        $Header.="\n";
    }else{
        # This must be a source file
        # TODO: This is very Microsoft-ish. Change this to make it useful for other C/C++ compilers
        $Header.="#pragma comment ( exestr, \"@(#)".ExpArchive()." ".ExpWorkFile()." ".Expevision()." ".ExpDate()."\")\n";
        $Header.="\n";
    }
    return $Header;
}

##############################################################################################################
#   Function:   Makes a footer for a CPP-header file
#   Parameters: 1. File Name
#   Returns:    Complete file footer
sub MakeCPPFileFooter
{
    my $self        = shift;
    my $FileName    = shift;
    # Check if it is a CPP header file from the name of the file
    my $IsHeader =~ /.+\.h$|.+\.hpp$|.+\.hxx$/i;
    if($IsHeader){
        my $Guard = MakeCPPHeaderFileGuard($FileName);
        return "#endif\t//..$Guard\n";
    }
    else{
        return "\n";
    }
}

##############################################################################################################
#   Function:   Makes a File header for any SQL file.
#               If it is for an Oracle package file, adds create or replace... script.
#   Parameters: 1. WIN32 or Unix File Name
#                   e.g. D:\Source\ITM\SQL\NYSE\pl_sql\tdb\packages\pg_clean.plb
#               2. Optional Schema Name, e.g. "tdb".
#                   If not specified, then we will attempt to extract if from file path.
#               3. Company Name for copyright notice
#               4. Author
#   Returns:    Complete file header
#   Tested:     23.4.01
sub MakeSQLFileHeader
{
    my $self        = shift;
    my $FileName    = shift;
    my $Schema      = shift;
    my $CompanyName = shift||$CompanyName;
    my $Author      = shift||$Author;
    # Get Package Name if it is one
    my $Package;
    if($FileName=~/(.+)\.(plb|plh)$/i){
        $Package = $1;
        if($Package=~/.*\\(.+)$/){
            $Package = $1;
        }
    }

    # Determine the type of file
    my $IsORAHeader;
    my $IsORABody;
    my $IsSQLScript;
    if((/.+\.plh$/i)){
        $IsORAHeader = 1;
    }elsif(/.+\.plb$/i){
        $IsORABody = 1;
    }elsif(/.+\.sql$/i){
        $IsSQLScript = 1;
    }

    # Get Schema name if not specified - this is only important for package headers
    if(!$Schema && ($IsORAHeader||$IsORABody)){
        /(.*\\|^)(.+)\\packages\\.+\..+$/i;
        $Schema = $2;
    }

    my $Header=BasicFileHeader('--',$CompanyName,$Author);
    if($IsORAHeader){
        if($Schema){
            $Header.="create or replace package $Schema.$Package as\n\n";
        }else{
            # Not ideal, as we need to be in this schema to correctly compile the package
            $Header.="create or replace package $Package as\n\n";
        }
    }elsif($IsORABody){
        if($Schema){
            $Header.="create or replace package body $Schema.$Package as\n\n";
        }else{
            # Not ideal, as we need to be in this schema to correctly compile the package
            $Header.="create or replace package body $Package as\n\n";
        }
    }
    return $Header;
}

##############################################################################################################
#   Function:   Makes a footer for an SQL File
#   Assumption: PLSQL header files have a "plh" extension
#               PLSQL body files have a "plb" extension
#   Parameters: 1. File Name
#               2. Author
#   Returns:    Complete file footer
#   Tested:     23.4.2001
sub MakeSQLFileFooter
{
    my $self        = shift;
    my $FileName    = shift;
    my $Footer;
    $Footer.="------------------------------------------------------------------------------\n";
    $Footer.="-- end of file\n";
    $Footer.="------------------------------------------------------------------------------\n";
    $Footer.="\n";
    return $Footer;
}

##############################################################################################################
#   Function:   Makes a Unix Shell script header for a file.
#               Use this when auto-generating perl script
#   Parameters: 1. SheBang line
#               2. Company Name for copyright notice
#               3. Author
#   Returns:    Complete file header
#   Tested:
sub MakeSHFileHeader
{
  my $self        = shift;
  my $shebang     = shift||"#!/bin/bash";
  my $CompanyName = shift||$CompanyName;
  my $Author      = shift||$Author;

  my $Header="$shebang\n";
  $Header.=BasicFileHeader('#',$CompanyName,$Author);
  return $Header;
}

##############################################################################################################
#   Function:   Makes a footer for a UNIX shell script file
#   Parameters: None
#   Returns:    Complete file footer
#   Tested:
sub MakeSHFileFooter
{
    my $self        = shift;
    my $Footer;
    $Footer.="#------------------------------------------------------------------------\n";
    $Footer.="# end of file\n";
    $Footer.="#------------------------------------------------------------------------\n";
    return $Footer;
}

##############################################################################################################
#   Function:   Makes a Windows batch script header for a file.
#   Parameters: 1. Company Name for copyright notice
#               2. Author
#   Returns:    Complete file header
#   Tested:
sub MakeWINFileHeader
{
  my $self        = shift;
  my $CompanyName = shift||$CompanyName;
  my $Author      = shift||$Author;
  my $Header=BasicFileHeader(':',$CompanyName,$Author);
  return $Header;
}

##############################################################################################################
#   Function:   Makes a footer for a Windows batch script file
#   Parameters: None
#   Returns:    Complete file footer
#   Tested:
sub MakeWINFileFooter
{
    my $self=shift;
    my $Footer;
    $Footer.=":------------------------------------------------------------------------\n";
    $Footer.=": end of file\n";
    $Footer.=":------------------------------------------------------------------------\n";
    return $Footer;
}

1;



