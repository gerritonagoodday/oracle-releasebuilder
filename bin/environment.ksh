#!/bin/bash
trap "rm -f $INPUT" INT TERM HUP EXIT
###############################################################################
###############################################################################
#  DESCRIPTION:
#  This script sets the Oracle Environemnt Variables, and can be run on its own
#  or as part of the Oracle Installation Suite.
#  This script will work with Oracle 8i, 9i and 10g.
#  It is intended to work on all Unices that support the KORN shell.
#
#  PREPARATION:
#  1. This script should be run from its curent directory.
#  2. This script should be executable. If unsure, type:
#     chmod +x environment
#  3. This script should be run as the Oracle Administrative user. This user
#    is usually configured as oracle:oinstall.
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
#  $ ./environment
#
#  NOTES:
#  Logfiles will be created in the 'log' directory. Refer to these for fault-
#  finding.
###############################################################################

###############################################################################
# Check that the value of ORACLE_SID is more or less correct.
# Set ORACLE_SID
###############################################################################
function GetOracleSID {
  if [[ -z $ORACLE_SID ]]
  then
    MSG="Enter the ORACLE_SID of the database\nthat you want install this release to:"
    $DIALOG --title "$TITLE" --inputbox "$MSG" 10 60 2>$INPUT
    cat $INPUT >>$LOGFILE
    IN_ORACLE_SID=$(cat $INPUT)
    IN_ORACLE_SID=$(echo $IN_ORACLE_SID|sed 's/ *//')
    if [[ -z $IN_ORACLE_SID ]]; then
      $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "Invalid entry." 0 0
      return 1
    else
      ORACLE_SID=$IN_ORACLE_SID
      MSG="ORACLE_SID is set to '${ORACLE_SID}'\nIs this correct?"
      $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
      [[ $? -eq 0 ]] && export ORACLE_SID && return 0
    fi
  else
    MSG="This release will be installed on database '${ORACLE_SID}'.\nIs this correct?"
    $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
    if [[ $? -ne 0 ]]; then
      MSG="Enter the ORACLE_SID of the target database\nor use the suggested value:"
      echo $MSG >>$LOGFILE
      $DIALOG --title "$TITLE" --inputbox "$MSG" 10 60 "${ORACLE_SID}" 2>$INPUT
      cat $INPUT >>$LOGFILE
      ORACLE_SID=$(cat $INPUT)
      if [[ ! -z ORACLE_SID ]]; then
        MSG="The target database of this release is '${ORACLE_SID}'.\nIs this correct?"
        echo $MSG >>$LOGFILE
        $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
        [[ $? -eq 0 ]] && export ORACLE_SID && return 0
        unset ORACLE_SID
        return 1
      fi
    fi
  fi

  # Check if this database has already been defined on this server
  # by  1. looking in the tnsnames.ora file
  # and 2. looking in the /etc/oratab file
  # If tnsnames.ora be found - else this is the first instance on the database
  if [[ -r $TNS_ADMIN/tnsnames.ora ]]; then
    # Extract all the SID's from the tnsnames.ora file
    TNS_SIDS=$(cat $TNS_ADMIN/tnsnames.ora | grep -i sid | grep -v '^ *#' | \
      sed 's/.*sid *= *//'|sed 's/.*= *//'|sed 's/\..*//g' |sed 's/[^a-zA-Z0-9]//g')
    TNS_SERVICES=$(cat $TNS_ADMIN/tnsnames.ora | grep -i service_name | grep -v '^ *#'  | \
      sed 's/.*service_name *= *//'|sed 's/.*= *//'|sed 's/\..*//g'|sed 's/[^a-zA-Z0-9]//g')
    SIDS="${TNS_SIDS} ${TNS_SERVICES}"
    echo "Inspecting file '$TNS_ADMIN/tnsnames.ora'" >> $LOGFILE
    for FOUND_SID in $SIDS; do
      if [[ $ORACLE_SID = $FOUND_SID ]]
      then
        MSG="Inspecting file '$TNS_ADMIN/tnsnames.ora'\n\nWarning:\nORACLE_SID '$ORACLE_SID' may already be in use by an existing database.\n\nAre you sure you want to continue?"
        echo $MSG >>$LOGFILE
        $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
        [[ $? -ne 0 ]] && unset ORACLE_SID && return 1
        export ORACLE_SID && return 0
      fi
    done

    # Not found in tnsnames.ora file. Look in oratab
    echo "Inspecting file '/etc/oratab'" >> $LOGFILE
    for FOUND_SID in $(cat /etc/oratab|grep -v "^#"|cut -f1 -d: -s); do
      if [[ $ORACLE_SID = $FOUND_SID ]]
      then
        MSG="Inspecting file '/etc/oratab'\n\nWarning:\nORACLE_SID '$ORACLE_SID' may already be in use by an existing database.\n\nAre you sure you want to continue?"
        echo $MSG >>$LOGFILE
        $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
        [[ $? -ne 0 ]] && unset ORACLE_SID return 1
      fi
    done
  fi

  # Check if the admin or data directories for this SID already exist
  # This is a very simplistic check - the data files will be in separate volumes for larger databases
  #if [[ -d $ORACLE_BASE/oradata/${ORACLE_SID} || -d $ORACLE_BASE/admin/${ORACLE_SID} ]]
  #then
  #  echo "It seems that a '${ORACLE_SID}' database already exists on this server."
  #  echo "Please select a different database instance."
  #  export ORACLE_SID
  #  return 1
  #fi

  # Final check:
  if [[ -z $ORACLE_SID ]]; then
    MSG="Could not determine the value of ORACLE_SID"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --infobox "$MSG" 0 0
    export ORACLE_SID=""
    return 1
  fi

  export ORACLE_SID
  return 0
}

###############################################################################
# Get installation Home absolute directory, as it is required for SQLPLUS
# which can still get a little confused with relative paths.
# This will be the one directory down from the directory that this
# file resides in
###############################################################################
function GetInstallationHomeDir {
  export INSTALLATION_HOME=${PWD%/*}
}

###############################################################################
# Get Oracle Owner details
###############################################################################
function GetOracleOwner {
  ORACLE_OWNER=$(id -un)
  ORACLE_GROUP=$(id -gn)

  MSG="You are currently logged in as user '$ORACLE_OWNER'\nwith primary group '$ORACLE_GROUP'.\nIs this the Oracle Admin. user?"
  echo $MSG >>$LOGFILE
  $DIALOG --title "$TITLE" --yesno "$MSG" 10 60
  [[ $? -eq 0 ]] && return 0
  MSG="Please log in as the Oracle Administrator and restart the installation process.\nExiting..."
  echo $MSG >>$LOGFILE
  $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0 &&  exit 1
}

###############################################################################
# Ensure that current user is in the same directory as the as this file
###############################################################################
function CheckUserCWD {
  # Simply check for the existence of a required file in the current directory
  MSG="You should be running this application from the directory in which it resides.\nYou are currently in directory ${PWD}.\nExiting..."
  echo $MSG >>$LOGFILE
  [[ ! -s install.ksh ]] && $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0 && exit 1
  return 0
}

###############################################################################
# Get the value of ORACLE_HOME and that it is more or less correct.
# Set ORACLE_HOME. This is typically set to /u01/app/oracle/product/10.1.0/db_1
###############################################################################
function GetOracleHome {
  # Get suggested value where Oracle has been installed
  WHICH_ORACLE_HOME=$(which oracle 2>/dev/null)

  if [[ -z $ORACLE_HOME ]]; then
    # Environment variable ORACLE_HOME is not set
    if [[ -z $WHICH_ORACLE_HOME ]]; then
      # Could not find Oracle installation. Make a suggestion out of the /etc/oratab file:
      if [[ -a /etc/oratab ]]; then
        echo "Inspecting file /etc/oratab..." >> $LOGFILE
        MAYBE_ORACLE_HOME=$(cat /etc/oratab|egrep -v "^ *#"|cut -d: -f2 -s)
        # Make picklist
        if [[ -n $MAYBE_ORACLE_HOME ]]; then
          if [[ $(echo $MAYBE_ORACLE_HOME| wc -l) -gt 1 ]]; then
            MSG="Oracle is/was installed at the following locations on this machine:\nPlease select one to use as the value for ORACLE_HOME:"
            echo $MSG >>$LOGFILE
            ITEMS=$(cat /etc/oratab|egrep -v "^ *#"|cut -d: -f2 -s|sed -e 's/^ *//')
            for ITEM in $ITEMS; do RADIOITEMS="${RADIOITEMS} ${ITEM} '' 'off' "; done
            $DIALOG --title "$TITLE" --radiolist "$MSG" 0 0 $(echo $ITEMS | wc -l ) $RADIOITEMS 2>$INPUT
            cat $INPUT >>$LOGFILE
            ORACLE_HOME=$(cat $INPUT)
          else
            MSG="Oracle is/was installed at the following location on this machine:"
            MSG="$MSG\n$MAYBE_ORACLE_HOME\nEnter a value for ORACLE_HOME, or accept the suggested value"
            echo $MSG >>$LOGFILE
            $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${MAYBE_ORACLE_HOME}" 2>$INPUT
            cat $INPUT >>$LOGFILE
            ORACLE_HOME=$(cat $INPUT)
          fi
        fi
      else
        MSG="Oracle does not seem to be installed on the server.\nExiting..."
        echo $MSG >>$LOGFILE
        $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --info "$MSG" 0 0
      fi
    else
      # Found a possible installation on the server in $WHICH_ORACLE_HOME
      WHICH_ORACLE_HOME=$(echo $WHICH_ORACLE_HOME|sed -e 's/\/bin\/oracle$//')
      WHICH_ORACLE_HOME_COUNT=$(echo $WHICH_ORACLE_HOME | wc -l)
      if [[ $WHICH_ORACLE_HOME_COUNT -gt 1 ]]; then
        # More than one Oracle installation on this machine
        MSG="Multiple Oracle installations appear to be on this machine.\nPlease select one to use as the value for ORACLE_HOME:"
        echo $MSG >>$LOGFILE
        for ITEM in ${WHICH_ORACLE_HOME}; do RADIOITEMS="${RADIOITEMS} ${ITEM} '' 'off' "; done
        $DIALOG --title "$TITLE" --radiolist "$MSG" 0 0 $(echo $ITEMS | wc -l ) $RADIOITEMS 2>$INPUT
        cat $INPUT >>$LOGFILE
        ORACLE_HOME=$(cat $INPUT)
      else
        MSG="An Oracle installation was found in ${WHICH_ORACLE_HOME}."
        MSG="$MSG\nEnter a value for ORACLE_HOME, or accept the suggested value"
        echo $MSG >>$LOGFILE
        $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${WHICH_ORACLE_HOME}" 2>$INPUT
        cat $INPUT >>$LOGFILE
        ORACLE_HOME=$(cat $INPUT)
      fi
    fi
  fi

  # Provide user entry
  ORACLE_HOME=$(echo $ORACLE_HOME|sed 's/ *//')
  if [[ -z $ORACLE_HOME ]]; then
    MSG="Could not determine a value for ORACLE_HOME.\nPlease enter a value for ORACLE_HOME"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "/u01/app/oracle/product/10.1.0/db_1" 2>$INPUT
    cat $INPUT >>$LOGFILE
    ORACLE_HOME=$(cat $INPUT)
  fi

  # Final check:
  MSG="ORACLE_HOME is set to ${ORACLE_HOME}.\nIs this correct?"
  echo $MSG >>$LOGFILE
  $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
  if [[ $? -eq 0 ]]; then
    export ORACLE_HOME
    # Set path if not already set
    if [[ -z $(echo ${PATH} | grep ${ORACLE_HOME}/bin) ]]; then
      export PATH=${ORACLE_HOME}/bin:${PATH}
    fi
    # Set ORACLE_DOC if not already set
    if [[ -z $ORACLE_DOC ]]; then
      export ORACLE_DOC=$ORACLE_HOME/doc
    fi
    return 0
  fi

  return 1
}

###############################################################################
# Check that the value of TNS_ADMIN is more or less correct.
# Set TNS_ADMIN
###############################################################################
function GetTNSAdmin {
  if [[ -z $TNS_ADMIN ]]; then
    MSG="Environment variable TNS_ADMIN is not set.\nAn Oracle installation is or will be installed in\n${ORACLE_HOME}. Enter a value for TNS_ADMIN:"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${ORACLE_HOME}/network/admin" 2>$INPUT
    cat $INPUT >>$LOGFILE
    TNS_ADMIN=$(cat $INPUT)
  else
    # TNS_ADMIN is defined - check that it points to a path
    TNS_ADMIN_BASE=$(echo $TNS_ADMIN|sed 's/\/network\/admin$//')
    if [[ ${ORACLE_HOME} != ${TNS_ADMIN_BASE} ]]; then
      MSG="TNS_ADMIN is currently set to\n${TNS_ADMIN}.\nNormally it would be set to ${ORACLE_HOME}/network/admin,\nas ORACLE_HOME is set to ${ORACLE_HOME}\nAccept the suggested value or enter a different value:"
      echo $MSG >>$LOGFILE
      $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${ORACLE_HOME}/network/admin" 2>$INPUT
      cat $INPUT >>$LOGFILE
      TNS_ADMIN=$(cat $INPUT)
    fi
  fi

  # Final check:
  TNS_ADMIN=$(echo $TNS_ADMIN|sed 's/ *//')
  if [[ -z $TNS_ADMIN ]]; then
    MSG="Could not determine the value of TNS_ADMIN. Exiting..."
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --infobox "$MSG" 0 0 && exit 1
  else
    MSG="TNS_ADMIN is set to\n${TNS_ADMIN}.\nIs this correct?"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
    [[ $? -eq 0 ]] && export TNS_ADMIN && return 0
  fi

  return 1
}

###############################################################################
# Check that the value of ORACLE_BASE is more or less correct.
# Set ORACLE_BASE. This is typically /u01/app/oracle
###############################################################################
function GetOracleBase {
  if [[ -z $ORACLE_BASE ]]; then
    echo ""
    # Get suggested value where Oracle has been installed
    ORACLE_BASE=$(echo $ORACLE_HOME | sed -e 's/oracle.*//')oracle
    MSG="Environment variable ORACLE_BASE is not set."
    if [[ ! -d $ORACLE_BASE ]]
    then
      MSG="$MSG\nCould not find Oracle installation. You either need to log on as the"
      MSG="$MSG\nOracle Admin. user, or set your path to point to the oracle binaries e.g."
      MSG="$MSG\n\n  \$ export PATH=[path to oracle binaries]:\$PATH\n"
    fi
    MSG="$MSG\nEnter a value for ORACLE_BASE, or accept the suggested value:"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${ORACLE_BASE}" 2>$INPUT
    cat $INPUT >>$LOGFILE
    ORACLE_BASE=$(cat $INPUT)
  else
    # ORACLE_BASE is defined - check that it points to a path
    if [[ ${ORACLE_BASE} != $(echo $ORACLE_HOME | sed -e 's/oracle.*//')oracle ]]; then
      MSG="ORACLE_BASE is currently set to\n${ORACLE_BASE}."
      MSG="$MSG\nNormally this would be set to $(echo $ORACLE_HOME | sed -e 's/oracle.*//')oracle"
      MSG="$MSG\nEnter a value for ORACLE_BASE, or accept the suggested value:"
      echo $MSG >>$LOGFILE
      $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "$(echo $ORACLE_HOME | sed -e 's/oracle.*//')oracle" 2>$INPUT
      cat $INPUT >>$LOGFILE
      ORACLE_BASE=$(cat $INPUT | sed -e 's/oracle.*//')oracle
    fi
  fi

  # Final check:
  ORACLE_BASE=$(echo $ORACLE_BASE|sed 's/ *//')
  if [[ -z $ORACLE_BASE ]]; then
    MSG="Could not determine the value of ORACLE_BASE"
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --infobox "$MSG" 0 0 && return 1
  else
    MSG="ORACLE_BASE is set to\n${ORACLE_BASE}\nIs this correct?"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
    [[ $? -ne 0 ]] && exit 1
  fi
  export ORACLE_BASE
  return 0
}

###############################################################################
# Gets / Sets the hostname of the server
###############################################################################
function GetTargetHostName {
  [[ -z ${HOSTNAME} ]] && HOSTNAME=$(hostname)
  if [[ -n ${HOSTNAME} ]]; then
    MSG="You are currently logged in to server '${HOSTNAME}'.\nIs this the server that you want\nto install this release on?"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
    if [[ $? -ne 0 ]]; then
      MSG="Please log on to the correct server\nand rerun this installation.\nExiting..."
      echo $MSG >>$LOGFILE
      $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --infobox "$MSG" 0 0
      exit 1
    fi
  fi
  if [[ -z ${HOSTNAME} ]]; then
    MSG="Enter the host name of the server that you are currently logged on to:"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "localhost" 2>$INPUT
    cat $INPUT >>$LOGFILE
    HOSTNAME=$(cat $INPUT)
    [[ -z $HOSTNAME ]] && $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --infobox "Invalid entry" 0 0 && return 1
  fi
  export ORACLE_HOST=$HOSTNAME
  return 0
}

###############################################################################
# Check if Oracle instance is running and attempt to start it if not
###############################################################################
function CheckStartInstance {
  MSG="Checking Oracle instance '${ORACLE_SID}'"
  $(sqlplus /nolog > $INPUT 2>/dev/null <<-!
  connect / as sysdba
  quit
!
  ) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0
  if [[ -n $(grep 'Connected' $INPUT) ]]; then
    if [[ -n $(grep 'idle instance' $INPUT) ]]; then
      MSG="Trying to start up instance '${ORACLE_SID}'"
      $(sqlplus -S /nolog > $INPUT <<-!
      connect / as sysdba
      startup
      quit
!
      ) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0
      if [[ -n $(grep 'failure' $INPUT) ]]
      then
        MSG="Oracle Instance '${ORACLE_SID}' exists on\n'${HOSTNAME}' but could not be started up"
        ORACLE_NEW=TRUE
      else
        MSG="Oracle Instance '${ORACLE_SID}' on\n'${HOSTNAME}' is now running"
      fi
    else
      MSG="Instance ${ORACLE_SID} on\n'${HOSTNAME}' is running"
    fi
  else
    # Could be because we are creating a new instance. This is OK.
    MSG="Oracle Instance '${ORACLE_SID}' does not\nyet exist on server '${HOSTNAME}'"
    ORACLE_NEW=TRUE
  fi
  echo $MSG >>$LOGFILE
  $(sleep ${SLEEP}) |$DIALOG --title "$TITLE" --infobox "$MSG" 0 0
  export ORACLE_NEW
  return 0
}

###############################################################################
# Get Oracle release number
# This can only be determined if there is already a database running on
# the server. Otherwise, the release number needs to be entered manually.
###############################################################################
function GetOracleRelease {
  if [[ -n ORACLE_NEW ]]; then
    MSG="Enter the full release number of Oracle that you are running:"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "10.1.0.2" 2>$INPUT
    cat $INPUT >>$LOGFILE
    ORACLE_RELEASE=$(cat $INPUT)
    [[ -z $ORACLE_RELEASE ]] && $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --infobox "Invalid entry" 0 0 && return 1
    export ORACLE_RELEASE
  else
    if [[ -z $(which sqlplus >/dev/null) ]]; then
      MSG="Could not find sqlplus on $HOSTNAME."
      $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --infobox "$MSG" 0 0 && return 1
    fi

    sqlplus -S "/ as sysdba" > $INPUT 2>/dev/null <<!
    set verify off
    set showmode off
    set feedback off
    set heading off
    select trim(max(substr(version,1,instr(version,'.')-1)))
      from sys.product_component_version
    where product like 'Oracle Database%';
!

    if [[ $? -ne 0 ]]; then
      MSG="Could not connect to Oracle."
      echo $MSG >>$LOGFILE
      $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --infobox "$MSG" 0 0 && return 1
    else
      ORACLE_RELEASE=$(cat $INPUT | sed -e 's/\n//g')
      if [[ -n $ORACLE_RELEASE ]]; then
        MSG="This is Oracle release ${ORACLE_RELEASE}"
        echo $MSG >>$LOGFILE
        $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --infobox "$MSG" 0 0
        export ORACLE_RELEASE
      else
        MSG="Enter the full release number of Oracle that you are running:"
        echo $MSG >>$LOGFILE
        $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "10.1.0.2" 2>$INPUT
        cat $INPUT >>$LOGFILE
        ORACLE_RELEASE=$(cat $INPUT)
        export ORACLE_RELEASE
      fi
    fi
  fi
  return 0
}

###############################################################################
# Ensure that current user has access to Oracle directories and binaries
###############################################################################
function CheckUserAccess {
  if [[ ! -w $ORACLE_BASE/admin && -d $ORACLE_BASE/admin ]]; then
    MSG="You need to log on as an Oracle Administrator to create configuration files\nin $ORACLE_BASE/admin. You are currently logged on as user $(whoami)"
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --msgbox "$MSG"  0 0
    return 1
  fi
  if [[ ! -w $ORACLE_BASE/oradata && -d $ORACLE_BASE/oradata ]]; then
    MSG="You need to log on as an Oracle Administrator to create data files\nin $ORACLE_BASE/oradata. You are currently logged on as user $(whoami)"
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --msgbox "$MSG"  0 0
    return 1
  fi
  if [[ ! -w $ORACLE_HOME/dbs && -d $ORACLE_HOME/dbs ]]; then
    MSG="You need to log on as Oracle Administrator to create configuration files\nin $ORACLE_HOME/dbs. You are currently logged on as user $(whoami)"
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --msgbox "$MSG"  0 0
    return 1
  fi
  if [[ ! -w ${PWD} ]]; then
    MSG="You need write access to the current directory, ${PWD}.\nYou are currently logged on as user $(whoami)"
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --msgbox "$MSG"  0 0 && return 1
  fi

  return 0
}

###############################################################################
# Get the location of where external procedures will be held.
# All external procedures will be assumed to be held in the same directory -
# if they aren't, then symbolic links should be created from this directory to
# wherever they are.
###############################################################################
function GetExtProcHomeDir {
  MSG="Enter the location where you want to keep all external procedures"
  echo $MSG >>$LOGFILE
  $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${ORACLE_BASE}/admin/${ORACLE_SID}/bin" 2>$INPUT
  cat $INPUT >>$LOGFILE
  EXT_PROC_HOME=$(cat $INPUT)
  export EXT_PROC_HOME
}

###############################################################################
# Set and get data directory
# This is typically /u02/oradata/${ORACLE_SID}
###############################################################################
function GetOracleDataDir {
  MSG="Enter the directory name that will hold the database data files"
  echo $MSG >>$LOGFILE
  $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "/u02/oradata/${ORACLE_SID}" 2>$INPUT
  cat $INPUT >>$LOGFILE
  ORACLE_DATA=$(cat $INPUT)
  if [[ -d $ORACLE_DATA ]]; then
    # The directory ${ORACLE_DATA} already exists
    if [[ $(ls ${ORACLE_DATA} | wc -l ) -gt 0 ]]; then
      MSG="Warning:\nThis directory already contains data files,\npossibly belonging to an existing database.\n"
      MSG="$MSG\nIf this release creates a new database,\nthen these files will be overwritten."
      MSG="$MSG\n\nAre you sure you want to continue?"
      echo $MSG >>$LOGFILE
      $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
      [[ $? -ne 0 ]] && return 1
    fi
  fi
  export ORACLE_DATA
}

###############################################################################
# Set and get rollback directory
###############################################################################
function GetRollbackSegment {
  MSG="Enter the directory name that will hold the database rollback segment files"
  echo $MSG >>$LOGFILE
  $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${ORACLE_DATA}" 2>$INPUT
  cat $INPUT >>$LOGFILE
  ROLLBACK_DIR=$(cat $INPUT)
  export ROLLBACK_DIR
}

###############################################################################
# Get the DBLINKS that are defined in the systemconf file
###############################################################################
function GetDBLinks {
  if [[ ! -z ${DATABASE_LINKS} ]]; then
    MSG="The database application expects the following database link\(s\) to be created:\n$(echo ${DATABASE_LINKS} | sed -e 's/ /, /')\n"
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --msgbox "$MSG"  0 0
    # Put values into arrays
    indexDL=0
    for item in ${DATABASE_LINKS}; do
      DL[${indexDl}]=$item
      indexDL=$((indexDL+1))
      if [[ $indexDL -gt 1023 ]]
      then
        MSG="Too many database links have been defined. The maximum is 1024.\nPlease correct the content of the systemconfig file and rerun this script.\nExiting..."
        echo $MSG >>$LOGFILE
        $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --msgbox "$MSG" 0 0
        exit 1
      fi
    done
    indexRD=0
    for item in ${REMOTE_DATABASES}; do
      RD[${indexRD}]=${item}
      indexRD=$((indexRD+1))
    done
    indexRU=0
    for item in ${REMOTE_USERS}; do
      RU[${indexRU}]=$item
      indexRU=$((indexRU+1))
    done
    indexRP=0
    for item in ${REMOTE_PASSWORDS}; do
      RP[${indexRP}]=$item
      indexRP=$((indexRP+1))
    done

    # Now have all the required information in arrays
    if [[ ${indexRD} -ne ${indexDL} || ${indexRD} -ne ${indexRU} ]]
    then
      MSG="The number of database links, remote users and passwords do not correspond.\nPlease correct the Database Links section of the systemconfig file.\nExiting..."
      echo $MSG >>$LOGFILE
      $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --msgbox "$MSG" 0 0 && exit 1
    fi
    # Modify dblink settings to suit target intallation environment
    index=0
    for DATABASE_LINK in ${DATABASE_LINKS}; do
      MSG="Enter the name of the remote database for DBLink ${DATABASE_LINK}"
      echo $MSG >>$LOGFILE
      $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${RD[${index}]}" 2>$INPUT
      cat $INPUT >>$LOGFILE
      RD[${index}]=$(cat $INPUT)
      MSG="Enter the password for the schema name ${RU[${index}]}\non the remote database ${RD[${index}]}"
      echo $MSG >>$LOGFILE
      $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${RP[${index}]}" 2>$INPUT
      cat $INPUT >>$LOGFILE
      RP[${index}]=$(cat $INPUT)
      index=$((index+1))
    done
    # Flatten out arrays into single environment variables
    REMOTE_DATABASES = ${RD[*]}
    REMOTE_PASSWORDS = ${RP[*]}
  else
    MSG="No remote connections to other databases have been defined."
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0
  fi
  return 0
}

###############################################################################
# Get the locations of Oracle Directory Objects
# These are predefined in the systemconfig file.
###############################################################################
function GetDirectoryPaths {
SED_COMMAND="sed \
  -e s!%ORACLE_HOST%!${ORACLE_HOST}!g \
  -e s!%ORACLE_HOME%!${ORACLE_HOME}!g \
  -e s!%ORACLE_SID%!${ORACLE_SID}!g \
  -e s!%ORACLE_DATA%!${ORACLE_DATA}!g \
  -e s!%ORACLE_RELEASE%!${ORACLE_RELEASE}!g \
  -e s!%ORACLE_BASE%!${ORACLE_BASE}!g"

  if [[ ! -z ${DIRECTORY_OBJECTS} ]]; then
    # Put values into arrays
    indexDO=0
    for item in ${DIRECTORY_OBJECTS}; do
      DO[${indexDO}]=$item
      indexDO=$((indexDO+1))
      if [[ $indexDO -gt 1023 ]]
      then
        MSG="Too many directory objects have been defined. The maximum is 1024.\nPlease correct the Directory Objects section of the systemconfig file.\nExiting..."
        echo $MSG >>$LOGFILE
        $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0 && exit 1
      fi
    done
    #
    DIRECTORY_LOCATIONS=$(echo $DIRECTORY_LOCATIONS | $SED_COMMAND)
    indexDL=0
    for item in ${DIRECTORY_LOCATIONS}; do
      DL[${indexDL}]=${item}
      indexDL=$((indexDL+1))
    done
    # Now have all the required information in arrays
    if [[ ${indexDO} -ne ${indexDL} ]]
    then
      MSG="The number of directory objects and locations do not correspond.\nPlease correct the content of the systemconfig file and rerun this script.\nExiting..."
      echo $MSG >>$LOGFILE
      $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0 && exit 1
    fi
    # Amend directory object paths to suit target environment
    index=0
    for DIRECTORY_OBJECT in ${DIRECTORY_OBJECTS}
    do
      MSG="Enter the name of the directory path for directory object ${DIRECTORY_OBJECT}:"
      echo $MSG >>$LOGFILE
      $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${DL[${index}]}" 2>$INPUT
      cat $INPUT >>$LOGFILE
      DL[${index}]=$(cat $INPUT)
      index=$((index+1))
    done
    # Flatten out modified arrays into single environment variable
    export DIRECTORY_LOCATIONS=${DL[*]}
  else
    $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "No directory objects have been defined." 0 0
  fi
  return 0
}

###############################################################################
# Get the locations of where the UTL_FILE package will read and write files to
# and from. These need to be defined in the init.ora file before Oracle
# will use them.
#
# TODO:
#  Figure out a good way to implement UTL_FILE_DIR without using the init.ora file.
#  This can be done using the DIRECTORY objects. Probably.
#  Also, there is also an error and events log directory that needs needs to be written to.
###############################################################################
function GetUtlFileDir {
SED_COMMAND="sed \
  -e s!%ORACLE_HOST%!${ORACLE_HOST}!g \
  -e s!%ORACLE_HOME%!${ORACLE_HOME}!g \
  -e s!%ORACLE_SID%!${ORACLE_SID}!g \
  -e s!%ORACLE_DATA%!${ORACLE_DATA}!g \
  -e s!%ORACLE_RELEASE%!${ORACLE_RELEASE}!g \
  -e s!%ORACLE_BASE%!${ORACLE_BASE}!g"

  if [[ ! -z ${UTL_FILE_DIRS} ]]
  then
    UTL_FILE_DIRS=$(echo $UTL_FILE_DIRS | $SED_COMMAND)
    # Put values into arrays
    index=0
    for UTL_FILE_DIR in ${UTL_FILE_DIRS}
    do
      index=$((index+1))
      if [[ $index -gt 1023 ]]
      then
        MSG="Too many UTL_FILE destinations have been defined. The maximum is 1024.\nPlease correct the UTL_FILE section of the systemconfig file.\nExiting..."
        echo $MSG >>$LOGFILE
        $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0 && exit 1
      fi
      MSG="Enter the UTL_FILE path ${index}:"
      echo $MSG >>$LOGFILE
      $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${UTL_FILE_DIR}" 2>$INPUT
      cat $INPUT >>$LOGFILE
      UF[${index}]=$(cat $INPUT)
    done
    # Flatten out modified array into single environment variable
    export UTL_FILE_DIRS=${UF[*]}
  else
    MSG="No UTL_FILE directories have been defined."
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0
  fi
  return 0
}

###############################################################################
# Get the number of CPU's on the server
###############################################################################
function GetNumberCPUs {
  ORACLE_CPUS=$(cat /proc/cpuinfo | grep processor | wc -l | sed -e 's/ //g')
  if [[ ORACLE_CPUS -eq 0 ]]; then
    MSG="Could not determine the number of CPU's on the server.\nEnter the number of CPU's on the server:"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "${UTL_FILE_DIR}" 2>$INPUT
    cat $INPUT >>$LOGFILE
    ORACLE_CPUS=$(cat $INPUT)
    if [[ -z $ORACLE_CPUS || $ORACLE_CPUS < "0" || $ORACLE_CPUS > "64" ]]; then
      MSG="Invalid number of CPU's. Assuming that there is only 1 CPU on the server."
      echo $MSG >>$LOGFILE
      $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0
      ORACLE_CPUS=1
    fi
  else
    MSG="The number of CPU's on found on this server is $ORACLE_CPUS.\nThis number will be used during the installation.\nIs this number correct?"
    echo $MSG >>$LOGFILE
    $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
    if [[ $? -ne 0 ]]; then
      MSG="Enter the number of CPU's that you want\nto configure the installation for:"
      echo $MSG >>$LOGFILE
      $DIALOG --title "$TITLE" --inputbox "$MSG" 0 0 "$ORACLE_CPUS" 2>$INPUT
      cat $INPUT >>$LOGFILE
      ORACLE_CPUS=$(cat $INPUT)
      if [[ -z $ORACLE_CPUS || $ORACLE_CPUS < "0" || $ORACLE_CPUS > "64" ]]; then
        MSG="Invalid number of CPU's. Assuming that there is only 1 CPU on the server."
        echo $MSG >>$LOGFILE
        $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0
        ORACLE_CPUS=1
      fi
    fi
  fi
  export ORACLE_CPUS
  return 0
}

###############################################################################
# Environment variables in profile name
###############################################################################
function SuggestOracleEnvironment {
  # Determine profile name
  if [[ $(uname) = 'Linux' ]]; then
    PROFILE="~/.bash_profile"
  else
    PROFILE="~/.profile"
  fi
  # Determine LD_ASSUME_KERNEL version
  if [[ $(uname) = 'Linux' ]]; then
    if [[ ${ORACLE_RELEASE:0:1} = "8" ]]; then
      KERNEL="2.2.5"
    fi
    if [[ ${ORACLE_RELEASE:0:1} = "9" ]]; then
      KERNEL="2.4.1"
    fi
  fi

  if [[ $(grep "^ *export +ORACLE_" $PROFILE | wc -l) -lt 5 ]]; then
    MSG="Suggestion:\n\
Add the following evironment variabls to $PROFILE is not already done so:\n\
export ORACLE_OWNER=${ORACLE_OWNER}\n\
export ORACLE_SID=${ORACLE_SID}\n\
export ORACLE_BASE=${ORACLE_BASE}\n\
export ORACLE_HOME=${ORACLE_HOME}\n\
export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$ORACLE_HOME/lib\n\
export TNS_ADMIN=${TNS_ADMIN}\n\
export ORA_NLS33=${ORACLE_HOME}/ocommon/nls/admin/data\n\
export ORACLE_TERM=xterm\n\
export PATH=\$PATH:${ORACLE_HOME}/bin\n"
    [[ -n $KERNEL ]] && MSG="$MSG\nexport LD_ASSUME_KERNEL=$KERNEL"
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP} ; sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0
  fi
  return 0
}

###############################################################################
# Create Environment variables file
###############################################################################
function CreateENVFile {
  echo "Writing environment variables" >>$LOGFILE
  [[ -a ${ORACLE_SID}_environment.ksh ]] && rm -f ${ORACLE_SID}_environment.ksh
  echo "#!/bin/bash" >> ${ORACLE_SID}_environment.ksh
  echo "###############################################################################" >> ${ORACLE_SID}_environment.ksh
  echo "# DESCRIPTION:" >> ${ORACLE_SID}_environment.ksh
  echo "# Environment settings for installing the database application" >> ${ORACLE_SID}_environment.ksh
  echo "# on database instance $ORACLE_SID on host $ORACLE_HOST" >> ${ORACLE_SID}_environment.ksh
  echo "# Created on $(date) by user $(id -un).">> ${ORACLE_SID}_environment.ksh
  echo "###############################################################################" >> ${ORACLE_SID}_environment.ksh
  echo "INSTALLATION_HOME=\"${INSTALLATION_HOME}\""      >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_HOST=\"${ORACLE_HOST}\""                  >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_SID=\"${ORACLE_SID}\""                    >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_DEFAULT=\"${ORACLE_DEFAULT}\""            >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_HOME=\"${ORACLE_HOME}\""                  >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_BASE=\"${ORACLE_BASE}\""                  >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_DATA=\"${ORACLE_DATA}\""                  >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_CPUS=\"${ORACLE_CPUS}\""                  >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_JOBS=\"${ORACLE_JOBS}\""                  >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_OWNER=\"${ORACLE_OWNER}\""                >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_GROUP=\"${ORACLE_GROUP}\""                >> ${ORACLE_SID}_environment.ksh
  echo "ROLLBACK_DIR=\"${ROLLBACK_DIR}\""                >> ${ORACLE_SID}_environment.ksh
  echo "TNS_ADMIN=\"${TNS_ADMIN}\""                      >> ${ORACLE_SID}_environment.ksh
  echo "ORACLE_RELEASE=\"${ORACLE_RELEASE}\""            >> ${ORACLE_SID}_environment.ksh
  echo "REMOTE_LINKS=\"${REMOTE_LINKS}\""                >> ${ORACLE_SID}_environment.ksh
  echo "REMOTE_USERS=\"${REMOTE_USERS}\""                >> ${ORACLE_SID}_environment.ksh
  echo "REMOTE_PASSWORDS=\"${REMOTE_PASSWORDS}\""        >> ${ORACLE_SID}_environment.ksh
  echo "REMOTE_DATABASES=\"${REMOTE_DATABASES}\""        >> ${ORACLE_SID}_environment.ksh
  echo "EXT_PROC_HOME=\"${EXT_PROC_HOME}\""              >> ${ORACLE_SID}_environment.ksh
  echo "UTL_FILE_DIRS=\"${UTL_FILE_DIRS}\""              >> ${ORACLE_SID}_environment.ksh
  echo "DIRECTORY_OBJECTS=\"${DIRECTORY_OBJECTS}\""      >> ${ORACLE_SID}_environment.ksh
  echo "DIRECTORY_LOCATIONS=\"${DIRECTORY_LOCATIONS}\""  >> ${ORACLE_SID}_environment.ksh
  echo "APPLICATION_SCHEMAS=\"${APPLICATION_SCHEMAS}\""  >> ${ORACLE_SID}_environment.ksh
  echo "###############################################################################" >> ${ORACLE_SID}_environment.ksh
  echo "# end of file" >> ${ORACLE_SID}_environment.ksh
  echo "###############################################################################" >> ${ORACLE_SID}_environment.ksh
  chmod +x ${ORACLE_SID}_environment.ksh
  mv -f ${ORACLE_SID}_environment.ksh ~/.orappi/.
  return 0
}

###############################################################################
# Create Environment variables SED file
###############################################################################
function CreateSEDFile {
  # Creating the sed file that will parse the environment variables
  [[ -a ${ORACLE_SID}_environment.sed ]] && rm -f ${ORACLE_SID}_environment.sed
  echo "#!/bin/sed" >> ${ORACLE_SID}_environment.sed
  echo "###############################################################################" >> ${ORACLE_SID}_environment.sed
  echo "# DESCRIPTION:" >> ${ORACLE_SID}_environment.sed
  echo "# This script changes all the marked input to previously-established" >> ${ORACLE_SID}_environment.sed
  echo "# environment variables. " >> ${ORACLE_SID}_environment.sed
  echo "# Created on $(date) by user $(id -un).">> ${ORACLE_SID}_environment.sed
  echo "###############################################################################" >> ${ORACLE_SID}_environment.sed
  echo "s/%INSTALLATION_HOME%/`echo ${INSTALLATION_HOME} | sed -e 's|\/|\\\/|g'`/g"      >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_HOST%/${ORACLE_HOST}/g"                  >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_SID%/`echo ${ORACLE_SID} | sed -e 's|\/|\\\/|g'`/g"                    >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_DEFAULT%/`echo ${ORACLE_DEFAULT} | sed -e 's|\/|\\\/|g'`/g"            >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_HOME%/`echo ${ORACLE_HOME} | sed -e 's|\/|\\\/|g'`/g"                  >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_BASE%/`echo ${ORACLE_BASE} | sed -e 's|\/|\\\/|g'`/g"                  >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_DATA%/`echo ${ORACLE_DATA} | sed -e 's|\/|\\\/|g'`/g"                  >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_CPUS%/`echo ${ORACLE_CPUS} | sed -e 's|\/|\\\/|g'`/g"                  >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_JOBS%/`echo ${ORACLE_JOBS} | sed -e 's|\/|\\\/|g'`/g"                  >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_OWNER%/`echo ${ORACLE_OWNER} | sed -e 's|\/|\\\/|g'`/g"                >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_GROUP%/`echo ${ORACLE_GROUP} | sed -e 's|\/|\\\/|g'`/g"                >> ${ORACLE_SID}_environment.sed
  echo "s/%ROLLBACK_DIR%/`echo ${ROLLBACK_DIR} | sed -e 's|\/|\\\/|g'`/g"                >> ${ORACLE_SID}_environment.sed
  echo "s/%TNS_ADMIN%/`echo ${TNS_ADMIN} | sed -e 's|\/|\\\/|g'`/g"                      >> ${ORACLE_SID}_environment.sed
  echo "s/%ORACLE_RELEASE%/`echo ${ORACLE_RELEASE} | sed -e 's|\/|\\\/|g'`/g"            >> ${ORACLE_SID}_environment.sed
  echo "s/%REMOTE_LINKS%/`echo ${REMOTE_LINKS} | sed -e 's|\/|\\\/|g'`/g"                >> ${ORACLE_SID}_environment.sed
  echo "s/%REMOTE_USERS%/`echo ${REMOTE_USERS} | sed -e 's|\/|\\\/|g'`/g"                >> ${ORACLE_SID}_environment.sed
  echo "s/%REMOTE_PASSWORDS%/`echo ${REMOTE_PASSWORDS} | sed -e 's|\/|\\\/|g'`/g"        >> ${ORACLE_SID}_environment.sed
  echo "s/%REMOTE_DATABASES%/`echo ${REMOTE_DATABASES} | sed -e 's|\/|\\\/|g'`/g"        >> ${ORACLE_SID}_environment.sed
  echo "s/%EXT_PROC_HOME%/`echo ${EXT_PROC_HOME} | sed -e 's|\/|\\\/|g'`/g"              >> ${ORACLE_SID}_environment.sed
  echo "s/%UTL_FILE_DIRS%/`echo ${UTL_FILE_DIRS} | sed -e 's|\/|\\\/|g'`/g"              >> ${ORACLE_SID}_environment.sed
  echo "s/%DIRECTORY_OBJECTS%/`echo ${DIRECTORY_OBJECTS} | sed -e 's|\/|\\\/|g'`/g"      >> ${ORACLE_SID}_environment.sed
  echo "s/%DIRECTORY_LOCATIONS%/`echo ${DIRECTORY_LOCATIONS} | sed -e 's|\/|\\\/|g'`/g"  >> ${ORACLE_SID}_environment.sed
  echo "s/%APPLICATION_SCHEMAS%/`echo ${APPLICATION_SCHEMAS} | sed -e 's|\/|\\\/|g'`/g"  >> ${ORACLE_SID}_environment.sed
  echo "###############################################################################" >> ${ORACLE_SID}_environment.sed
  echo "# end of file" >> ${ORACLE_SID}_environment.sed
  echo "###############################################################################" >> ${ORACLE_SID}_environment.sed
  chmod +x ${ORACLE_SID}_environment.sed
  mv -f ${ORACLE_SID}_environment.sed ~/.orappi/.
  return 0
}

###############################################################################
# MAIN
###############################################################################
# Set up log file
[[ ! -d log ]] && mkdir log
LOGFILE=$(basename $0)
LOGFILE=log/${LOGFILE%\.*}.log
rm -f $LOGFILE
touch $LOGFILE

INPUT=".input.$$"
# Number of seconds for info messages to appear
SLEEP=4

# Check if the tools directory is present
# =======================================
if [[ ! -d ../tools ]]; then
  echo "The tools directory is not present. Exiting..." | tee -a  $LOGFILE
  exit 1
fi

# Check if either Xdialog or dialog is installed
if [[ -z $(which "Xdialog") && -z $(which "dialog") && \
      ! -x ../tools/Xdialog && -x ../tools/dialog ]]; then
  echo "Neither Xdialog nor dialog are installed." | tee -a $LOGFILE
  echo "Install at least the dialog program to continue."  | tee -a $LOGFILE
  echo "Exiting..."  | tee -a $LOGFILE
  exit 1
fi

# Check which environment we are in
# =================================
if [[ -z $DISPLAY ]]; then
  echo "Text-based installation" >> $LOGFILE
  DIALOG=dialog
else
  # Text if Xdialog exists
  XDIALOG=$(which Xdialog 2>/dev/null)
  if  [[ -z $XDIALOG ]]; then
    if [[ ! -x "../tools/Xdialog" ]]; then
      # Are in X11 environment but Xdialog does not exist - resort to text mode
      DIALOG=dialog
    else
      XDIALOG="../tools/Xdialog"
    fi
  fi
  # Final test if Xdialog will run
  if [[ -n $XDIALOG ]]; then
    $XDIALOG --title "Test" --infobox "Test" 1 1 1 2>$LOGFILE
    if [[ $? -eq 0 ]]
    then
      echo "X11-based installation" >> $LOGFILE
      DIALOG=$XDIALOG
    else
      DIALOG=dialog
    fi
  fi
fi


# Get environment
# ===============
. ./systemconfig


# Get Release details
# ===================
if [[ -z $RELEASE ]]; then
   # Get Release name from release file
  [[ ! -r RELEASE ]] && echo "The RELEASE file could not be found. Exiting..." && exit 1
  RELEASE_NAME=$(grep "^ *RELEASE_NAME *=" RELEASE)
  [[ ${#RELEASE_NAME[*]} > 1 ]] && printf "Too many releases in the RELEASE note defined.\nExiting...\n"  | tee -a  $LOGFILE && exit 1
  [[ ${#RELEASE_NAME[*]} = 0 ]] && printf "The RELEASE note does not define this installation's Release.\nExiting...\n"  | tee -a  $LOGFILE && exit 1
  eval ${RELEASE_NAME}
  RELEASE=$RELEASE_NAME
fi
[[ -n $RELEASE ]] && RELEASETXT="Release ${RELEASE} -"


# Server environment
# ==================
TITLE="$RELEASETXT Determining the server environment"


GetTargetHostName
[[ $? -ne 0 ]] && exit 1
# Check that user is correct
GetOracleOwner
[[ $? -ne 0 ]] && exit 1
# Check that user is in correct directory
CheckUserCWD
[[ $? -ne 0 ]] && exit 1


# Installation Environment
# ========================
TITLE="${RELEASETXT} Determining the Installation environment"
GetOracleSID
while [[ $? -ne 0 ]]; do
  $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "Trying again" 0 0
  GetOracleSID
done
[[ $? -ne 0 ]] && exit 1


# If an existing configuration exists, choose to use it
if [[ -e ~/.orappi/${ORACLE_SID}_environment.ksh &&
      -e ~/.orappi/${ORACLE_SID}_environment.sed ]]; then
  MSG="The installation environment for ORACLE_SID '${ORACLE_SID}'\nhas previously been configured.\nDo you want to rerun the configuration?"
  echo $MSG >>$LOGFILE
  $DIALOG --title "$TITLE" --yesno "$MSG" 0 0
  if [[ $? -ne 0 ]]; then

    # Update install directory (note subshell!) if the INSTALLATION_HOME or DIRECTORY_OBJECTS has changed
    . ~/.orappi/${ORACLE_SID}_environment.ksh
    OLD_INSTALLATION_HOME=$INSTALLATION_HOME
    OLD_DIRECTORY_OBJECTS=$DIRECTORY_OBJECTS
    GetInstallationHomeDir
    GetDirectoryPaths
    if [[ $OLD_INSTALLATION_HOME != $INSTALLATION_HOME || \
          $OLD_DIRECTORY_OBJECTS != $DIRECTORY_OBJECTS ]]; then
      MSG="Using and updating the existing '${ORACLE_SID}' environment configuration."
      # Rewrite output files with correct INSTALLATION_HOME value
      CreateENVFile
      CreateSEDFile
    else
      MSG="Using the existing '${ORACLE_SID}' environment configuration."
    fi
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --infobox "$MSG" 0 0
    exit 0
  else
    MSG="Reconfiguring the environment for '${ORACLE_SID}'"
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP})|$DIALOG --title "$TITLE" --infobox "$MSG" 0 0
  fi
fi

# Establish home dir for this installation
GetInstallationHomeDir
[[ $? -ne 0 ]] && exit 1

GetNumberCPUs
ORACLE_JOBS=$((ORACLE_CPUS*2+1))

# Database environment
# ====================
TITLE="${RELEASETXT} Determining the Database environment"
GetOracleHome
[[ $? -ne 0 ]] && exit 1
CheckStartInstance
[[ $? -ne 0 ]] && exit 1
GetOracleRelease
[[ $? -ne 0 ]] && exit 1
GetOracleBase
[[ $? -ne 0 ]] && exit 1
CheckUserAccess
[[ $? -ne 0 ]] && exit 1
GetTNSAdmin
[[ $? -ne 0 ]] && exit 1

# Oracle file locations
# =====================
TITLE="${RELEASETXT} Determining Oracle file locations"
# TODO: This is very simplistic, and does not account for multiple storage devices etc...
echo "Configuring the Oracle data file location:" >>$LOGFILE
GetOracleDataDir
while [[ $? -ne 0 ]]
do
  $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "Trying again" 0 0
  GetOracleDataDir
done

echo "Configuring the Oracle rollback segment location:" >>$LOGFILE
GetRollbackSegment
while [[ $? -ne 0 ]]
do
  $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "Trying again" 0 0
  GetRollbackSegment
done

echo "Configuring the Oracle Remote connections:" >>$LOGFILE
GetDBLinks
if [[ $? -ne 0 ]];then exit 1;fi

echo "Configuring the external procedures directory:" >>$LOGFILE
GetExtProcHomeDir
while [[ $? -ne 0 ]]
do
  $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "Trying again" 0 0
  GetExtProcHomeDir
done

echo "Configuring actual paths for Oracle Directory Objects:" >>$LOGFILE
GetDirectoryPaths
while [[ $? -ne 0 ]]
do
  $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "Trying again" 0 0
  GetDirectoryPaths
done

echo "Configuring the UTL_FILE directories:" >>$LOGFILE
GetUtlFileDir
while [[ $? -ne 0 ]]
do
  $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "Trying again" 0 0
  GetUtlFileDir
done

# Copying the configuration files to the server's central repository
[[ ! -d ~/.orappi ]] && mkdir -p ~/.orappi

CreateENVFile
CreateSEDFile


MSG="Environment configuration successfully completed"
echo $MSG >>$LOGFILE
$(sleep ${SLEEP} ) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0

#SuggestOracleEnvironment

exit 0
