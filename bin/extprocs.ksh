#!/bin/bash
###############################################################################
###############################################################################
#  DESCRIPTION:
#  This script invokes all the extprocs of the installation.
#
#  USAGE:
#  As user oracle:
#  $ %ORACLE_SID%_extprocs.ksh
###############################################################################

# The make.ksh files can only be run from the source code directory of the
# external procedured.
CURRENT_PWD=$(pwd)

# {{ ORAPPI_INSTALLATION_BEGIN }}


# {{ ORAPPI_INSTALLATION_END }}

cd ${CURRENT_PWD}
exit 0

###############################################################################
# END OF FILE
###############################################################################





