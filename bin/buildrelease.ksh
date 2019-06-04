#!/bin/bash
# Time to display info dialogs
SLEEP=4
# Hardcoded Oracle Admin name to create an install
ORACLE_OWNER="oracle"
CURRENT_PWD=$(pwd)
INPUT=".input.$$"
PASSWD=".passwd"
trap "rm -f $PASSWD $INPUT ; cd $CURRENT_PWD" INT TERM HUP EXIT
###############################################################################
###############################################################################
#  DESCRIPTION:
#  This script builds a release package
#
#  PREPARATION:
#  1. This script can be run from the current directory only
#  2. This script should be executable. If unsure, type:
#     chmod +x buildrelease.ksh
#  3. Read the file BUILDING
#
#  USAGE:
#    $ su - oracle
#    Password:
#    $ export ORACLE_SID=<instance_name>
#    $ chmod +x buildrelease.ksh
#    $ ./buildrelease.ksh
###############################################################################

# Make up dialog title
TITLE="Building release"

# Set up log file
[[ ! -d log ]] && mkdir log
LOGFILE=$(basename $0)
LOGFILE=${CURRENT_PWD}/log/${LOGFILE%\.*}.log
rm -f $LOGFILE
touch $LOGFILE
chmod 666 $LOGFILE

# Check if either Xdialog or dialog is installed
if [[ -z $(which "Xdialog") && -z $(which "dialog") && \
    ! -x ./Xdialog && -x ./dialog ]]; then
  echo "Neither Xdialog nor dialog are installed." | tee -a $LOGFILE
  echo "Install at least the dialog program to continue."  | tee -a $LOGFILE
  echo "Exiting..."  | tee -a $LOGFILE
  exit 1
fi

# Check which environment we are in
if [[ -z $DISPLAY ]]; then
  echo "Text-based installation" | tee -a  $LOGFILE
  DIALOG=dialog
else
  # Text if Xdialog exists
  XDIALOG=$(which Xdialog 2>/dev/null)
  if [[ -z $XDIALOG ]]; then
    if [[ ! -x "./Xdialog" ]]; then
      # Are in X11 environment but Xdialog does not exist - resort to text mode
      DIALOG=dialog
    else
      XDIALOG="./Xdialog"
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

# Check current user
#if [[ ${LOGNAME} != ${ORACLE_OWNER} ]]; then
#  MSG="You are not user '${ORACLE_OWNER}', you\nare user '$LOGNAME'!\n\nRerun this script and log in as\nuser '${ORACLE_OWNER}' to continue.\n\nExiting...\n"
#  echo "$MSG" >> $LOGFILE
#  $DIALOG --title "$TITLE" --msgbox "$MSG" 12 41
#  exit 1
#fi

# Get build number from user
MSG="Enter the Build number for which you
want to create an installation package.
This should be in the form 'buildXXX'
where XXX is a zero-padded 3-digit value:"
$DIALOG --title "$TITLE" --inputbox "$MSG" 15 45 "$RELEASE" 2>$INPUT
if [[ $? -ne 0 ]]; then
  echo "Build cancelled by user" >> $LOGFILE
  exit 1
fi
RELEASE=$(cat $INPUT) && rm -f $INPUT
RELEASE=${RELEASE% *}

# Check Build Id format
if [[ -n $(echo $RELEASE | sed -e 's/^build[0-9]\{3\}//')  || -z $RELEASE ]]; then
  MSG="Invalid format specified for Build Id:\n\n[$RELEASE]\n\nExiting..."
  echo "$MSG" >> $LOGFILE
  $DIALOG --title "$TITLE" --msgbox "$MSG" 0 0
  exit 1
fi

export $RELEASE

# Check if build directory is present
BUILD_DIR="$PWD/../$RELEASE"
if [[ ! -d $BUILD_DIR ]]; then
  MSG="Directory [$BUILD_DIR] does not exist.\nExiting..."
  echo "$MSG" >> $LOGFILE
  $DIALOG --title "$TITLE" --msgbox "$MSG" 0 0
  exit 1
fi

# Check if a RELEASE FILE has been defined
if [[ ! -e ${BUILD_DIR}/install/RELEASE ]]; then
  MSG="The release note ${BUILD_DIR}/install/RELEASE could not be found.\nExiting..."
  echo "$MSG" >> $LOGFILE
  $DIALOG --title "$TITLE" --msgbox "$MSG" 0 0
  exit 1
fi

# Check that the RELEASE NAME in the RELEASE note ties up
RELEASE_NAME=$( grep "^ *RELEASE_NAME *=" ${BUILD_DIR}/install/RELEASE )
if [[ ${#RELEASE_NAME[*]} > 1 ]]; then
  MSG="Too many releases in the RELEASE note defined.\nPlease correct the RELEASE note.\nExiting..."
  echo "$MSG" >> $LOGFILE
  $DIALOG --title "$TITLE" --msgbox "$MSG" 0 0
  exit 1
fi
if [[ ${#RELEASE_NAME[*]} = 0 ]]; then
  MSG="The RELEASE note does not define this installation's Release.\nPlease correct the RELEASE note.\nExiting..."
  echo "$MSG" >> $LOGFILE
  $DIALOG --title "$TITLE" --msgbox "$MSG" 0 0
  exit 1
fi
eval ${RELEASE_NAME}
RELEASENOTE_RELEASE=${RELEASE_NAME}

#if [[ ${RELEASENOTE_RELEASE} != ${RELEASE} ]]; then
#  MSG="The RELEASE note refers to this release as\n'${RELEASENOTE_RELEASE}',\n whereas you are attempting to build release\n'${RELEASE}'.\nPlease correct the RELEASE note '${BUILD_DIR}/install/RELEASE'.\nExiting..."
# echo "$MSG" >> $LOGFILE
#  $DIALOG --title "$TITLE" --msgbox "$MSG" 0 0
# exit 1
#fi

# Check if the files necessary for a minimum installation are present
if [[ ! -e ${BUILD_DIR}/install/environment.ksh ]]; then
  MSG="The file ${BUILD_DIR}/install/environment.ksh is not present. Exiting..."
  echo "$MSG" >> $LOGFILE
  $DIALOG --title "$TITLE" --msgbox "$MSG" 0 0
  exit 1
fi

# Check if the files necessary for a minimum installation are present
MINFILES="systemconfig install.ksh environment.ksh cleanup.ksh uninstall.sql RELEASE INSTALL UNINSTALL TROUBLESHOOTING"
for MINFILE in $systemconfig; do
  if [[ ! -e ${BUILD_DIR}/install/${MINFILE} ]]; then
    MSG="The following files are required in a minimum installation:\n$MINFILES\nThe file '${MINFILE}' is missing. Exiting..."
    echo "$MSG" >> $LOGFILE
    $DIALOG --title "$TITLE" --msgbox "$MSG" 0 0
    exit 1
  fi
done

MSG="Creating installation for release '$BUILD'"
echo "$MSG" >> $LOGFILE
# Display progress:
# Only display this after input has been requested,
# as text-based dialog does not support multiple windows
$DIALOG --title "$TITLE" --no-cancel --tailbox $LOGFILE 21 70 &
# If there were any previous errors then show them
[[ ! -z $ERROR ]] && sleep $SLEEP

echo "Removing old log directories" >>$LOGFILE
find ${BUILD_DIR} -name log -exec rm -fr {} >>$LOGFILE \;
echo " ">> $LOGFILE

echo "Converting text files to Unix format" >>$LOGFILE
find ${BUILD_DIR} -path '*' -type f -exec dos2unix {} 2>>$LOGFILE \; -exec chmod -v 666 {} 1>>$LOGFILE \;
echo " ">> $LOGFILE

echo "Setting executable files" >>$LOGFILE
find ${BUILD_DIR} -path '*.ksh' -type f -exec chmod -v 755 {} 1>>$LOGFILE \;
find ${BUILD_DIR} -path '*.pl'  -type f -exec chmod -v 755 {} 1>>$LOGFILE \;
echo " ">> $LOGFILE

BUILDER_PWD=$(pwd)
echo "Creating the Tar-ball package ${RELEASE}.tar.gz\n\n" >>$LOGFILE
cd ${BUILD_DIR}/../.
PACKAGE_NAME=${RELEASE}.tar.gz
rm -f "${PACKAGE_NAME}"
tar -czf "${PACKAGE_NAME}" ${RELEASE} 2>/dev/null
[[ $? -ne 0 ]] && ERROR=TRUE;
if [[ -z $ERROR ]]; then
 [[ ! -d ${BUILDER_PWD}/packages ]] && mkdir -p ${BUILDER_PWD}/packages
 mv $PACKAGE_NAME ${BUILDER_PWD}/packages/.
 echo "The package '$PACKAGE_NAME' is in the directory\n${BUILDER_PWD}/packages" >>$LOGFILE
fi
cd -


if [[ -z $ERROR ]]; then
  echo "Successfully created installation package.\n\n" >> $LOGFILE
  echo "To install the package, copy it to the target server and do the following:\n" >>$LOGFILE
  echo "  \$ scp ${BUILDER_PWD}/packages/$PACKAGE_NAME ${ORACLE_OWNER}@<server>:~/." >>$LOGFILE
  echo "  \$ ssh ${ORACLE_OWNER}@<server>" >>$LOGFILE
  echo "  \$ tar -xzvf $PACKAGE_NAME " >>$LOGFILE
  echo "  \$ cd ${RELEASE}/install " >>$LOGFILE
  echo "  \$ ./install.ksh " >>$LOGFILE
  echo "  " >>$LOGFILE
  echo "DONE." >>$LOGFILE
else
  echo "***************************************************" >> $LOGFILE
  echo "There were errors in creating release 'RELEASE'."    >> $LOGFILE
  echo "Refer to $LOGFILE for details."                      >> $LOGFILE
  echo "***************************************************" >> $LOGFILE
fi
echo " ">> $LOGFILE

# Wait for shut down of progress dialog
wait

exit 0
# Do not modify the code above this line!
