#!/bin/bash
# Remove critical remnants on a crash
PASSWD=".passwd"
trap "rm -f $PASSWD" INT TERM HUP EXIT
###############################################################################
###############################################################################
#  DESCRIPTION:
#  This script patches a previous patch level
#  The previous RELEASE can be determined by subtracting 1 from the build Id
#  indicated in the source filename above.
#
#  Warning: This installation file is specifically crafted install on the
#           previous release. Running this release on the wrong release
#           will have unpredictable results.
#
#  PREPARATION:
#  1. This script can be run from the current directory only
#  2. This script should be executable. If unsure, type:
#     chmod +x install.ksh
#  3. You should know the root password before attempting to run this script
#     as this script may require you to perform superuser operations.
#
#  USAGE:
#    $ su - oracle
#    Password:
#    $ export ORACLE_SID=<instance_name>
#    $ chmod +x install.ksh
#    $ ./install.ksh
###############################################################################


###############################################################################
# Main
###############################################################################

# Set up log file
[[ ! -d log ]] && mkdir log
LOGFILE=$(basename $0)
LOGFILE=log/${LOGFILE%\.*}.log
rm -f $LOGFILE
touch $LOGFILE

# Get Release name from release file
[[ ! -r RELEASE ]] && echo "The RELEASE file could not be found. Exiting..." && exit 1
RELEASE_NAME=$(grep "^ *RELEASE_NAME *=" RELEASE)
[[ ${#RELEASE_NAME[*]} > 1 ]] && printf "Too many releases in the RELEASE note defined.\nExiting...\n"  | tee -a  $LOGFILE && exit 1
[[ ${#RELEASE_NAME[*]} = 0 ]] && printf "The RELEASE note does not define this installation's Release.\nExiting...\n"  | tee -a  $LOGFILE && exit 1
eval ${RELEASE_NAME}
RELEASE=$RELEASE_NAME
export RELEASE
SLEEP=4

# Make up dialog title
TITLE="Release '${RELEASE}': Install"

# Check if the tools directory is present
if [[ ! -d ../tools ]]; then
  echo "The tools directory is not present. Exiting..." | tee -a  $LOGFILE
  exit 1
fi

# Check if either Xdialog or dialog is installed
if [[ -z $(which "Xdialog" 2>/dev/null) && -z $(which "dialog" 2>/dev/null) ]]; then
  printf "Neither Xdialog nor dialog are installed.\n" | tee -a $LOGFILE
  printf "Install at least the 'dialog' program to continue.\n" | tee -a $LOGFILE
  printf "Exiting...\n" | tee -a $LOGFILE
  exit 1
fi

# Check which environment we are in
if [[ -z $DISPLAY ]]; then
  printf "Text-based installation\n" >> $LOGFILE
  DIALOG=dialog
else
  # Text if Xdialog exists
  XDIALOG=$(which Xdialog 2>/dev/null)
  if [[ -z $XDIALOG ]]; then
    if [[ ! -x "$PWD/../tools/Xdialog" ]]; then
      # Are in X11 environment but Xdialog does not exist - resort to text mode
      DIALOG=dialog
    else
      XDIALOG="$PWD/../tools/Xdialog"
    fi
  fi
  # Final test if Xdialog will run
  if [[ -n $XDIALOG ]]; then
    $XDIALOG --title "Test" --infobox "Test" 1 1 1 2>$LOGFILE
    if [[ $? -eq 0 ]]; then
      DIALOG=$XDIALOG
    else
      DIALOG=dialog
    fi
  fi
fi

echo "Loading Environment..." >>$LOGFILE
if [[ ! -a environment.ksh ]]; then
  MSG="The script 'environment.ksh' is missing from the intstallation.\nExiting..."
  echo $MSG >>$LOGFILE
  $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0
  exit 1
fi
./environment.ksh
[[ $? -ne 0 ]] && ERROR=TRUE
cat log/environment.log >>$LOGFILE

echo "Reading Environment..." >>$LOGFILE
if [[ -z $ERROR ]]; then
  if [[ ! -a ~/.orappi/${ORACLE_SID}_environment.ksh &&
        ! -a ~/.orappi/${ORACLE_SID}_environment.sed ]]; then
    MSG="The installer expected to find the file\n~/.orappi/${ORACLE_SID}_environment.ksh.\nExiting..."
    echo $MSG >>$LOGFILE
    $(sleep ${SLEEP}) | $DIALOG --title "$TITLE" --infobox "$MSG" 0 0
    exit 1
  fi
  . ~/.orappi/${ORACLE_SID}_environment.ksh
fi

# Perform root operations if a root.ksh file existed in the installation
if [[ -z $ERROR ]]; then
  if [[ -a root.ksh ]]; then
    OBJECT=root
    sed -f ~/.orappi/${ORACLE_SID}_environment.sed ${OBJECT}.ksh > ${ORACLE_SID}_${OBJECT}.ksh 2>> $LOGFILE
    $DIALOG --title "$TITLE" --passwordbox "Enter root password for $HOSTNAME" 8 55 2>$PASSWD
    [[ $? -ne 0 || -z $(cat $PASSWD) ]] && rm -f $PASSWD && echo "Root password entry failed. Exiting..." >> $LOGFILE && exit 1
    pw=$(cat $PASSWD) ; rm -f $PASSWD
    echo "Performing root operations\n" >> $LOGFILE
    expect -d -  1>>${LOGFILE} 2>/dev/null <<-!
    spawn "/bin/bash"
    send "su\r"
    expect -re "Password: "
    sleep 1
    send "$pw\r"
    expect -re "#"
    send "./${ORACLE_SID}_root.ksh\r"
    expect -re "#"
!
    echo "\nRoot operations complete\n" >> $LOGFILE
    [[ $? -ne 0 ]] && ERROR=TRUE

  fi
fi

# Display progress:
# Only display this after (interactive) root password input has been requested,
# as text-based dialog does not support multiple windows
[[ -z $LINES ]] && LINES=21
[[ -z $COLUMNS ]] && COLUMNS=70
$DIALOG --title "$TITLE" --no-cancel --tailbox $LOGFILE $LINES $COLUMNS &
# If there were any previous errors then show them
sleep $SLEEP

# Create ORACLE_SID-based KORN scripts
KORN_OBJECTS="analyse extprocs custom_begin custom_end logrotate"
for OBJECT in $KORN_OBJECTS; do
  if [[ -a ${OBJECT}.ksh ]]; then
    echo "Creating $OBJECT file" >> $LOGFILE
    # Objects correspond to an <object>.ksh file name in this directory
    sed -f ~/.orappi/${ORACLE_SID}_environment.sed ${OBJECT}.ksh > ${ORACLE_SID}_${OBJECT}.ksh 2>> $LOGFILE
    chmod +x ${ORACLE_SID}_${OBJECT}.ksh 2>> $LOGFILE
    # Prepare log file
    [[ -a log/${ORACLE_SID}_${OBJECT}.log ]] && rm -f log/${ORACLE_SID}_${OBJECT}.log
  fi
done

# Create server-based objects
KORN_OBJECTS="custom_begin analyse extprocs logrotate custom_end"
for OBJECT in $KORN_OBJECTS; do
  if [[ -a ${ORACLE_SID}_${OBJECT}.ksh ]]; then
    echo "Implementing ${ORACLE_SID}_${OBJECT}.ksh" >> $LOGFILE
    ./${ORACLE_SID}_${OBJECT}.ksh >> log/${ORACLE_SID}_${OBJECT}.log
    cat log/${ORACLE_SID}_${OBJECT}.log >> $LOGFILE
  fi
done

# Create ORACLE_SID-based SQL files
ORACLE_OBJECTS="catalogs custom_begin custom_end database data dblinks directories exceptions \
                functions jobs libraries packages privileges procedures roles \
                sequences synonyms tables tablespaces triggers types uninstall \
                users views"
for OBJECT in $ORACLE_OBJECTS; do
  if [[ -a ${OBJECT}.sql ]]; then
    echo "Creating ${ORACLE_SID}_${OBJECT}.sql file" >> $LOGFILE
    # Objects correspond to an <object>.sql file name in this directory
    sed -f ~/.orappi/${ORACLE_SID}_environment.sed ${OBJECT}.sql > ${ORACLE_SID}_${OBJECT}.sql
    # Prepare log file
    [[ -a log/${ORACLE_SID}_${OBJECT}.log ]] && rm -f log/${ORACLE_SID}_${OBJECT}.log
  fi
done

# Create objects by running SQL files in the most logical order
# (which is not alway possible)
ORACLE_OBJECTS="custom_begin tablespaces catalogs roles users types tables data dblinks directories \
                libraries sequences synonyms functions procedures packages exceptions \
                views jobs privileges triggers custom_end"
for OBJECT in $ORACLE_OBJECTS; do
  if [[ -a ${ORACLE_SID}_${OBJECT}.sql ]]; then
    # Create objects
    echo "Creating $OBJECT" >> $LOGFILE
    sqlplus -s / as sysdba >> $LOGFILE 2>/dev/null <<-!
      @${ORACLE_SID}_${OBJECT}.sql
!
    # Check for errros
    if [[ ! -z $(grep 'ORA-' log/${ORACLE_SID}_${OBJECT}.log) ]]; then
      ERROR_FILE=log/${ORACLE_SID}_errors
      # Create error code summary with explanations
      echo "Error Explanations:" > $ERROR_FILE
      echo "------------------" >> $ERROR_FILE
      for LINE in $(awk '/ORA-[0-9]/ { print $1 }' log/${ORACLE_SID}_${OBJECT}.log | sort -u | sed 's/://')
      do
        oerr $(echo $LINE | sed -e 's/-/ /') >> $ERROR_FILE
        echo " " >> $ERROR_FILE
      done

      # Inform user console
      echo " "
      echo "Errors when running ${ORACLE_SID}_${OBJECT}.sql:" >> $LOGFILE
      echo "-------------" >> $LOGFILE
      grep 'ORA-' log/${ORACLE_SID}_${OBJECT}.log | sort -u >> $LOGFILE
      cat $ERROR_FILE >> $LOGFILE
      echo " " >> $LOGFILE
      echo "Refer to log/${ORACLE_SID}_${OBJECT}.log for context details.\n" >> $LOGFILE
      rm -f $ERROR_FILE
    fi
  fi
done

if [[ -e "${INSTALLATION_HOME}/tools/compile.sql" ]]; then
  echo "Compiling database" >> $LOGFILE
  sqlplus -s / as sysdba @${INSTALLATION_HOME}/tools/compile.sql >> $LOGFILE
  [[ $? -ne 0 ]] && ERROR=TRUE
else
  echo "* Compilation script\n  '${INSTALLATION_HOME}/tools/compile.sql' is missing." >> $LOGFILE
  echo "  Please compile the database manually using the following command:" >> $LOGFILE
  echo "  sqlplus / as sysdba @../tools/compile.sql" >> $LOGFILE
fi

if [[ -z $ERROR ]]; then
  MSG="Updating PatchLevel to $RELEASE in '$ORACLE_SID'"
  echo $MSG >> $LOGFILE
  sqlplus -s / as sysdba >> $LOGFILE <<-!
  whenever SQLERROR exit failure
  whenever OSERROR exit failure
  update utl.tb_config
     set string_value='$RELEASE',
         tmstmp=sysdate
   where upper(variable)=upper('PatchLevel');
  commit;
!
  [[ $? -ne 0 ]] && ERROR=TRUE
fi

if [[ -z $ERROR ]]; then
  MSG="Release '${RELEASE}' successfully installed."
else
  MSG="There were errors in installing release '${RELEASE}'.\nRefer to ${LOGFILE} for details."
fi
echo $MSG >> $LOGFILE
sleep $SLEEP
echo "\nHit Return to close this window.\n" >> $LOGFILE
sleep $SLEEP
# Wait for shut down of progress dialog
wait

exit 0

