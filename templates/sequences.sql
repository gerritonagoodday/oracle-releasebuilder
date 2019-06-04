------------------------------------------------------------------------------
------------------------------------------------------------------------------
--  DESCRIPTION:
--  Sequence installation file for database %ORACLE_SID% on %ORACLE_HOST%.
--
--  USAGE:
--  $ export ORACLE_SID=%ORACLE_SID%
--  $ sqlplus "sys/<password> as sysdba" install/@%ORACLE_SID%_sequences.sql
--  This will restore all states in the application if they already exist.
--
--  ORIGIN:
--  This file was originally generated by the ScriptSequences.sql utility
--  from the database venom1 on 28JUL2004 15:01:00.
--  by user GHoekstra on Oracle client CIVICAUK\CORNHOLIO
------------------------------------------------------------------------------
whenever SQLERROR exit failure
spool log/%ORACLE_SID%_sequences.log
whenever OSERROR exit failure
set serveroutput on size 1000000;
set pagesize 0
set verify off
set feedback off

-- {{ ORAPPI_INSTALLATION_BEGIN }}


-- {{ ORAPPI_INSTALLATION_END }}

spool off
disconnect
exit
------------------------------------------------------------------------------
-- end of file
------------------------------------------------------------------------------
