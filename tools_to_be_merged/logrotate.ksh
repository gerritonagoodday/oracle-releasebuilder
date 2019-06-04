#!/bin/bash
###############################################################################
#  File name:                  $Workfile: logrotate.ksh $
#  Revision:                   $Revision: 4 $
#  Last checked in on:         $Date: 16/08/04 12:42 $
#  Last modified by:           $Author: Ghoekstra $
#  Source file location:       $Archive: /DWH/Oracle/install/logrotate.ksh $
###############################################################################
#  DESCRIPTION:
#  This script generates the logrotate script that will be keep the
#  %ORACLE_SID% log size under control.
#
#  PREPARATION:
#  1. This script can be run from any directory.
#  2. This script should be executable. If unsure, type:
#     chmod +x %ORACLE_SID%_analyse
#  3. This script should be run as the Oracle Admin. user. This user is usually
#     configured as oracle:oinstall.
#
#  USAGE:
#  Ideally, this script should be run in a regular basis.
#  This can be implemented by adding it to a Oracle Admin's crontab:
#  As user oracle:
#  $ crontab -e
#  i (for insert mode)
#  05 0 * * * /usr/sbin/logrotate -s %ORACLE_BASE%/admin/%ORACLE_SID%/log/logrotate.status %ORACLE_BASE%/admin/%ORACLE_SID%/log/logrotate.conf
#  <esc>:wq
#
###############################################################################
LOG_DIR=%ORACLE_BASE%/admin/%ORACLE_SID%/log
[[ ! -d ${LOG_DIR} ]] && mkdir ${LOG_DIR}

echo "Creating daily logrotate job"

LOGROTATE=/usr/sbin/logrotate
# Check that logrotate is installed
if [[ ! -e $LOGROTATE  && $(which logrotate) -ne 0 ]]; then
  echo "The logrotate program does not seem to be installed on the server."
  echo "Please install it at a later stage to $LOGROTATE."
  echo "The rest of the logrotate installation will proceed"
fi

cat >$LOG_DIR/logrotate.conf<<-!
# Rotate files daily and keep for 35 days = 5 weeks, ca. one month.
# GZIP rotated files
${LOG_DIR}/events {
    daily
    rotate 35
    missingok
    compress
    delaycompress
    notifempty
    create 640 %ORACLE_OWNER% %ORACLE_GROUP%
    sharedscripts
    copytruncate
}
!

echo "Do not remove the logrotate.conf and the logrotate.status files!" > ${LOG_DIR}/README

echo "Log rotation will run daily at 5 minutes past midnight."
echo "You can modify user %ORACLE_OWNER%'s crontab entry to change"
echo "the time if it does not suit you using the following command:"
echo "  \$ export EDITOR=nano"
echo "  \$ crontab -e"
echo "\n"
# This will remove all comments from the crontab
(crontab -l | grep -v ${LOGROTATE} | grep -v '#'; echo "05 0 * * * ${LOGROTATE} -s ${LOG_DIR}/logrotate.status ${LOG_DIR}/logrotate.conf")|crontab

exit 0

###############################################################################
# END OF FILE
###############################################################################





