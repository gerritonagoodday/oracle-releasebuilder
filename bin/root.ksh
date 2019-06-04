#!/bin/bash
###############################################################################
###############################################################################
#  DESCRIPTION:
#  This script performs any operations that need to be performed by user root.
#  It can only be run by user root.
#
#  All events are sent to STDOUT, which is captured by the installation
#  script and shown on the log-viewing screen,
#
#  USAGE:
#    $ su - root
#    Password:
#    $ export ORACLE_SID=<instance_name>
#    $ chmod +x %ORACLE_SID%_root.ksh
#    $ ./%ORACLE_SID%_root.ksh
###############################################################################

###############################################################################
# Create the Oracle startup script
#
# These operations require the root password when prompted
#
###############################################################################
function SetOracleServices {
  echo "Adding Oracle to the system service and setting it to start after a reboot..."
  cp oracle /etc/init.d/.
  [[ ! -x /etc/init.d/oracle ]] && chmod +x /etc/init.d/oracle
  /sbin/chkconfig --add oracle
  /sbin/chkconfig --levels 345 oracle on
  return 0
}


###############################################################################
# ROOT SERVER INSTALLATION
###############################################################################
echo " "
echo "Root Server configuration"
echo "========================="
echo " "

SetOracleServices

exit 0
