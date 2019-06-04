------------------------------------------------------------------------
------------------------------------------------------------------------
--  DESCRIPTION:
--  Oracle custom script configuration file which is run near the
--  beginning of the installation.
--  This file is manually created for the database instance
--  %ORACLE_SID% on %ORACLE_HOST% and is specific to this release.
--  It normally only contains the skeleton.
--  It is invoked near the end of the installation before the compilation.
--
--  LIMITATIONS:
--  No interactive commands can be performed from here.
--
--  USAGE:
--  $ export ORACLE_SID=%ORACLE_SID%
--  $ sqlplus "sys/<password> as sysdba" @%ORACLE_SID%_custom_begin.sql
------------------------------------------------------------------------
whenever SQLERROR exit failure
whenever OSERROR exit failure
set serveroutput on size 1000000;
set pagesize 0
set verify off
set feedback off
set pages 100

connect / as sysdba
spool log/%ORACLE_SID%_custom_begin.log

-- {{ ORAPPI_INSTALLATION_BEGIN }}


-- {{ ORAPPI_INSTALLATION_END }}

spool off
disconnect
exit;

------------------------------------------------------------------------
-- end of file
------------------------------------------------------------------------
