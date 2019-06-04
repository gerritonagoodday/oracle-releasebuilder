#!/bin/bash
###############################################################################
###############################################################################
#  DESCRIPTION:
#  Removes all traces of the installation from the installation directory,
#  including temporary files and log files.
#
#  PREPARATION:
#  1. This script should be run from its current directory.
#  2. This script should be executable. If unsure, type:
#     chmod +x cleanup
#  3. This script should be run as the Oracle Admin. user. This user is usually
#     configured as oracle:oinstall.
#  4. Ensure that the Oracle Admin. user has read and write access to the
#     current and all child directories
#
#  USAGE:
#  You must be logged on as the Oracle Adminstrator (normally 'oracle').
#  Run the script from the console by typing the following:
#  $ export ORACLE_SID=<instance_name>
#  $ ./cleanup.ksh
#
###############################################################################

[[ -z $ORACLE_SID ]] && echo "\$ORACLE_SID has not been defined. Exiting..." && exit 1

echo Cleaning up temporary installation files...
[[ ! -a ${ORACLE_SID}_* ]] && echo "No installation files found."
rm -f ${ORACLE_SID}_*

echo Cleaning up log files...
[[ ! -a log/${ORACLE_SID}_* ]] && echo "No log files found."
rm -f log/${ORACLE_SID}_*


echo Done.
