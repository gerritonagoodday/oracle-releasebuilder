------------------------------------------------------------------------
------------------------------------------------------------------------
--  DESCRIPTION:
--  Oracle instance configuration file
--  This file is automatically generated for the database
--  instance %ORACLE_SID% on %ORACLE_HOST%
--
--  USAGE:
--  USAGE:
--  sqlplus /nolog @%ORACLE_SID%_database.sql
------------------------------------------------------------------------
whenever SQLERROR exit failure
whenever OSERROR exit failure
set serveroutput on size 1000000;
set pagesize 0
set verify off
set feedback off
set pages 100

connect / as sysdba

spool log/%ORACLE_SID%_database.log
set echo on
startup nomount pfile=%ORACLE_HOME%/dbs/init%ORACLE_SID%.ora

-- The following throws some itneresting errors on 10g.
-- Spend some time reading documentation perhaps?
-- Need to specify SYSAUX, SYSTEM, UNDO etc...

CREATE DATABASE %ORACLE_SID%
  MAXLOGFILES 5
  MAXLOGMEMBERS 2
  MAXDATAFILES 500
  MAXINSTANCES 1
  MAXLOGHISTORY 1
  CHARACTER SET WE8ISO8859P1
DATAFILE '%ROLLBACK_DIR%/%ORACLE_SID%_system.dbf' SIZE 10M  REUSE AUTOEXTEND ON NEXT 10240K
LOGFILE GROUP 1 ('%ROLLBACK_DIR%/redo1a.log','%ROLLBACK_DIR%/redo1b.log') SIZE 1M REUSE,
        GROUP 2 ('%ROLLBACK_DIR%/redo2a.log','%ROLLBACK_DIR%/redo2b.log') SIZE 1M REUSE,
        GROUP 3 ('%ROLLBACK_DIR%/redo3a.log','%ROLLBACK_DIR%/redo3b.log') SIZE 1M REUSE,
        GROUP 4 ('%ROLLBACK_DIR%/redo4a.log','%ROLLBACK_DIR%/redo4b.log') SIZE 1M REUSE;
spool off
disconnect
exit;
------------------------------------------------------------------------
-- end of file
------------------------------------------------------------------------

