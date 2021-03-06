------------------------------------------------------------------------
------------------------------------------------------------------------
--  DESCRIPTION:
--  Oracle instance configuration file
--  This file is automatically generated using tools.
--
--  USAGE:
--  USAGE:
--  sqlplus /nolog @%ORACLE_SID%_catalogs.sql
------------------------------------------------------------------------
--whenever SQLERROR exit failure
--whenever OSERROR exit failure
set serveroutput on size 1000000;
set pagesize 0
set verify off
set feedback off
set pages 100

connect / as sysdba
spool log/%ORACLE_SID%_catalogs.log
prompt There are many silly errors in the Oracle catalog that are of no
prompt consequence. We can safely ignore them.
spool off

-- These are only necessary when creating a new database installation
-- Example:
--prompt Creating Oracle data dictionary views:
--@%ORACLE_HOME%/rdbms/admin/catalog.sql;
--prompt Creating Oracle system procedures:
--@%ORACLE_HOME%/rdbms/admin/catproc.sql;
--prompt Creating internal views for Export/Import utility:
--@%ORACLE_HOME%/rdbms/admin/catexp.sql;

-- {{ ORAPPI_INSTALLATION_BEGIN }}


-- {{ ORAPPI_INSTALLATION_END }}

-- This should only be run once for the installation
prompt Creating DBMS_SHARED_POOL packages
@%ORACLE_HOME%/rdbms/admin/dbmspool.sql;

--spool off
disconnect
exit;

------------------------------------------------------------------------
-- end of file
------------------------------------------------------------------------
