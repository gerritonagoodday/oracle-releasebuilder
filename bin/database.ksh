#!/bin/bash
###############################################################################
###############################################################################
#  DESCRIPTION:
#  This script creates an empty Oracle database, and can be run on its own
#  or as part of the Oracle Installation Suite.
#  This script will work with Oracle 8i and 9i. And probably Oracle 10g too.
#  It is intended to work on all Unices that support the KORN shell.
#
#  PREPARATION:
#  1. This script should be run from its curent directory.
#  2. This script should be executable. If unsure, type:
#     chmod +x database
#  3. This script should be run as the Oracle Admin. user. This user is usually
#     configured as oracle:oinstall.
#  4. Ensure that the Oracle Admin. user has read and write access to the
#     current and all child directories.
#  5. The Oracle RDBMS product should be installed on the target server.
#  6. Establish where the desired data file directories should be. If you
#     are not sure, then this installation program will suggest commonly-used
#     directories.
#  7. Decide on a name for the database.
#
#  USAGE:
#  This installation must be run from a console on the target server.
#  You must be logged on as the Oracle Adminstrator (normally 'oracle').
#  Run the script from the console by typing the following and hitting Return:
#  $ ./database.ksh
#
#  NOTES:
#  Logfiles will be created in the 'log' directory. Refer to these for fault-
#  finding.
###############################################################################


###############################################################################
# Set TNSNAMES.ORA
###############################################################################
function SetTNSNames {
  sed -f ${ORACLE_SID}_environment.sed tnsnames.ora >> ${ORACLE_SID}_tnsnames.ora
  if [[ -s ${TNS_ADMIN}/tnsnames.ora ]]
  then
    if [[ ! -O ${TNS_ADMIN}/tnsnames.ora ]]
    then
      echo "You do not have Write access to the existing TNSNAMES configuration file ${TNS_ADMIN}/tnsnames.ora."
      echo "Please mannually amend this file using the example given in the file ${ORACLE_SID}_tnsnames.ora."
      return 0
    else
      # File exists and can write to it
      # Check if ORACLE_SID has not already been defined
      if [[ $(grep -n -i ${ORACLE_SID} ${TNS_ADMIN}/tnsnames.ora) -ne 0 ]]
      then
        echo "It appears that a configuration for this ORACLE_SID, ${ORACLE_SID}, already exists in the file ${TNS_ADMIN}/tnsnames.ora."
        echo "Please amend this file using the example given in the file ${ORACLE_SID}_tnsnames.ora in the current directory."
      else
        echo "Appending the configuration for the new ORACLE_SID ${ORACLE_SID} to ${TNS_ADMIN}/tnsnames.ora..."
        sed -f ${ORACLE_SID}_environment.sed tnsnames.ora >> ${TNS_ADMIN}/tnsnames.ora
      fi
    fi
  else
    echo "Creating a new TNSNAMES configuration file in ${TNS_ADMIN}/tnsnames.ora..."
    sed -f ${ORACLE_SID}_environment.sed tnsnames.ora >> ${TNS_ADMIN}/tnsnames.ora
    ERRNO=$?
    if [[ $ERRNO -ne 0 ]]
    then
      echo "Failed to create the configuration file ${TNS_ADMIN}/tnsnames.ora. Please mannually amend this file using the example file ${ORACLE_SID}_tnsnames.ora in the current directory."
      return $ERRNO
    fi
  fi

  return 0
}

###############################################################################
# Set LISTENER.ORA in $TNS_NAMES directory
###############################################################################
function SetListener {
  sed -f ${ORACLE_SID}_environment.sed listener.ora >> ${ORACLE_SID}_listener.ora
  if [[ -s ${TNS_ADMIN}/listener.ora ]]
  then
    echo "There is already an existing LISTENER configuration file "
    echo "${TNS_ADMIN}/listener.ora."
    echo "Please mannually amend this file using the examples given in the file "
    echo "${ORACLE_SID}_listener.ora."
    return 0
  else
    echo "Creating a new LISTENER configuration file in ${TNS_ADMIN}/listener.ora..."
    echo "# LISTENER.ORA Network Configuration File:">> ${TNS_ADMIN}/listener.ora
    echo "# ${TNS_ADMIN}/listener.ora"               >> ${TNS_ADMIN}/listener.ora
    sed -f ${ORACLE_SID}_environment.sed listener.ora >> ${TNS_ADMIN}/listener.ora
    ERRNO=$?
    if [[ $ERRNO -ne 0 ]]
    then
      echo "Failed to set up the ${TNS_ADMIN}/listner.ora file. Error $ERRNO. Please mannually amend this file."
    fi
  fi
  return 0
}


###############################################################################
# Check if Oracle instance is running and attempt to start it if not
###############################################################################
function CheckStartInstance {
  echo "Checking Oracle instance ${ORACLE_SID}:"
  TMPFILE=/tmp/${ORACLE_SID}$$
  ORACLE_SID=${ORACLE_SID} sqlplus /nolog > ${TMPFILE} 2>/dev/null <<-!
  connect / as sysdba
  quit
!
  if [[ -n $(grep 'Connected' ${TMPFILE}) ]]
  then
    if [[ -n $(grep 'idle instance' ${TMPFILE}) ]]
    then
      sqlplus -S /nolog > ${TMPFILE} <<-!
      connect / as sysdba
      startup
      quit
!
      if [[ -n $(grep 'failure' ${TMPFILE}) ]]
      then
        echo "Instance ${ORACLE_SID} on ${HOSTNAME} has not yet been created on Oracle"
      else
        echo "Instance ${ORACLE_SID} on ${HOSTNAME} is running"
      fi
    else
      echo "Instance ${ORACLE_SID} is running"
    fi
  else
    # Could be because we are creating a new instance. This is OK.
    echo "Instance ${ORACLE_SID} does not yet exist on ${HOSTNAME}"
    export ORACLE_NEW=TRUE
    rm -f ${TMPFILE}
    return 0
  fi
  rm -f ${TMPFILE}
  return 0
}

###############################################################################
# Startup Database and show NLS-based ASCII table for Database
###############################################################################
function StartupDatabase {
  CheckStartInstance
  [[ $? -ne 0 ]] && return 1

  echo "The ASCII table as seen by ORACLE:"
  echo "============================================================="
  sqlplus -S "/ as sysdba" <<-!
  set echo off
  set feedback off
  whenever SQLERROR exit failure
  whenever OSERROR exit failure
  set serveroutput on size 10240
  declare
    i number;
    j number;
    k number;
  begin
    for i in 2..15 loop
      for j in 1..16 loop
        k:=i*16+j;
        dbms_output.put((to_char(k,'000'))||':'||chr(k)||'  ');
        if k mod 8 = 0 then
          dbms_output.put_line('');
        end if;
      end loop;
     end loop;
  end;
/
!
  err=$?
  echo "============================================================="
  return $err
}


###############################################################################
# ORACLE DATABSE CREATION
###############################################################################
. ./systemconfig
echo " "
echo "Oracle Database Creation"
echo "========================"
echo " "

if [[ -a ${ORACLE_SID}_environment.ksh ]]
then
  . ./${ORACLE_SID}_environment.ksh
  if [[ -z ${ORACLE_SID} || -z ${ORACLE_HOME} || -z ${ROLLBACK_DIR} || -z ${ORACLE_DATA} || -z ${ORACLE_BASE} || -z ${TNS_ADMIN} || -z ${ORACLE_RELEASE} ]]
  then
    echo "One or more required configuration values to create a database are not defined."
    ./environment.ksh
    [[ $? -ne 0 ]] && exit $?
  else
    ./${ORACLE_SID}_environment.ksh
    [[ $? -ne 0 ]] && exit $?
  fi
else
  ./environment.ksh
  [[ $? -ne 0 ]] && exit $?
fi

echo "Creating data directory $ORACLE_DATA"
[[ ! -d $ORACLE_DATA ]] && mkdir -p $ORACLE_DATA
if [[ ! -d $ORACLE_DATA ]]
then
  echo "Could not create directory $ORACLE_DATA."
  exit 1
fi

echo "Creating base configuration directory"
echo "  $ORACLE_BASE/admin/$ORACLE_SID"
[[ ! -d $ORACLE_BASE/admin/$ORACLE_SID ]] && mkdir -p $ORACLE_BASE/admin/$ORACLE_SID
if [[ ! -d $ORACLE_BASE/admin/$ORACLE_SID ]]
then
  echo "Could not create directory ${ORACLE_BASE}/admin/${ORACLE_SID}."
  exit 1
fi

echo "Building configuration directories in ${ORACLE_BASE}/admin/${ORACLE_SID}"
echo "  $ORACLE_BASE/admin/$ORACLE_SID"
test ! -d $ORACLE_BASE/admin/$ORACLE_SID/pfile  && mkdir -p $ORACLE_BASE/admin/$ORACLE_SID/pfile
echo "  $ORACLE_BASE/admin/$ORACLE_SID/create"
test ! -d $ORACLE_BASE/admin/$ORACLE_SID/create && mkdir -p $ORACLE_BASE/admin/$ORACLE_SID/create
echo "  $ORACLE_BASE/admin/$ORACLE_SID/udump"
test ! -d $ORACLE_BASE/admin/$ORACLE_SID/udump  && mkdir -p $ORACLE_BASE/admin/$ORACLE_SID/udump
echo "  $ORACLE_BASE/admin/$ORACLE_SID/bdump"
test ! -d $ORACLE_BASE/admin/$ORACLE_SID/bdump  && mkdir -p $ORACLE_BASE/admin/$ORACLE_SID/bdump
echo "  $ORACLE_BASE/admin/$ORACLE_SID/cdump"
test ! -d $ORACLE_BASE/admin/$ORACLE_SID/cdump  && mkdir -p $ORACLE_BASE/admin/$ORACLE_SID/cdump


echo "Creating External procedures directory"
if [[ -z $EXT_PROC_HOME && ! -d $EXT_PROC_HOME ]]
then
  mkdir -p $EXT_PROC_HOME
  if [[ ! -d $EXT_PROC_HOME ]]
  then
    echo "Could not create directory $EXT_PROC_HOME"
  fi
fi

echo "Creating UTL_FILE directories"
for dir in $UTL_FILE_DIRS
do
  echo "  $dir"
  if [[ ! -d $dir ]]
  then
    mkdir -p $dir
    if [[ ! -d $dir ]]
    then
      echo "Could not create directory $dir"
    fi
  fi
done

echo "Creating directories for Oracle directory objects"
for dir in $DIRECTORY_LOCATIONS
do
  echo "  $dir"
  if [[ ! -d $dir ]]
  then
    mkdir -p $dir
    if [[ ! -d $dir ]]
    then
      echo "Could not create directory $dir"
    fi
  fi
done

echo "Install init${ORACLE_SID}.ora"
sed -f ${ORACLE_SID}_environment.sed init.ora > ${ORACLE_SID}_init.ora
for dir in $UTL_FILE_DIRS
do
  echo "utl_file_dir = $dir" >> ${ORACLE_SID}_init.ora
done
cp -f ${ORACLE_SID}_init.ora $ORACLE_BASE/admin/${ORACLE_SID}/pfile/init${ORACLE_SID}.ora

echo "Create Symbolic link to init${ORACLE_SID}.ora in "
ln -fs $ORACLE_BASE/admin/${ORACLE_SID}/pfile/init${ORACLE_SID}.ora $ORACLE_HOME/dbs/init${ORACLE_SID}.ora

echo "Starting listener"
lsnrctl start >/dev/null

# Run some of the ORACLE_SID-based files
ORACLE_OBJECTS="database tablespaces catalogs"
for OBJECT in $ORACLE_OBJECTS
do
  # Prepare log file
  [[ -a log/${ORACLE_SID}_${OBJECT}.log ]] && rm -f log/${ORACLE_SID}_${OBJECT}.log
  sed -f ${ORACLE_SID}_environment.sed ${OBJECT}.sql > ${ORACLE_SID}_${OBJECT}.sql
  echo "Creating $OBJECT"
  sqlplus -s /nolog > /dev/null <<-!
  @${ORACLE_SID}_${OBJECT}.sql
!
  # Check for errros
  if [[ ! -z $(grep 'ORA-' log/${ORACLE_SID}_${OBJECT}.log) ]]
  then
    # Create error code summary with explanations
    echo "Explanations:" >  log/${ORACLE_SID}_errors
    echo "-------------" >> log/${ORACLE_SID}_errors
    for LINE in $(awk '/ORA-[0-9]/ { print $1 }' log/${ORACLE_SID}_${OBJECT}.log | sort -u | sed 's/://')
    do
      oerr $(echo $LINE | sed -e 's/-/ /') >> log/${ORACLE_SID}_errors
      echo " " >> log/${ORACLE_SID}_errors
    done

    # Inform user console
    echo " "
    echo "* The following errors occurred when running ${OBJECT}.sql:"
    echo "Errors:"
    echo "-------"
    grep 'ORA-' log/${ORACLE_SID}_${OBJECT}.log | sort -u
    cat log/${ORACLE_SID}_errors
    echo "Refer to log/${ORACLE_SID}_${OBJECT}.log for context details."
    exit 1
  fi
done

# tested up to here!
SetTNSNames
SetListener
StartupDatabase

echo " "
echo "Database successfully created."
echo " "

exit 0
