------------------------------------------------------------------------------
------------------------------------------------------------------------------
--  DESCRIPTION:
--  Oracle database link creation.
--
--  This file is generated for the Oracle instance %ORACLE_SID%
--  on %ORACLE_HOST%
--
--  USAGE:
--  $ export ORACLE_SID=%ORACLE_SID%
--  $ sqlplus %REMOTE_LINKOWNER%/<password> @%REMOTE_LINKOWNER%/dblinks/%REMOTE_LINK%.sql
--
--
--  The database link name:         %REMOTE_LINK%
--  owned by local owner:           %REMOTE_LINKOWNER%
--  connecting to remote user:      %REMOTE_USER%
--  with password:                  %REMOTE_PASSWORD%
--  for access to remote database:  %REMOTE_DATABASE%
--
--  The resulting command  that is executed is:
--  SQL> create database link %REMOTE_LINK%
--    2  connect to %REMOTE_USER%
--    3  identified by %REMOTE_PASSWORD%
--    4  using ''%REMOTE_DATABASE%'';
--
--  Fault finding:
--  1. ORA-02085: database link %REMOTE_LINK% connects to %REMOTE_DATABASE%
--  Cause:  a database link connected to a database with a different name.
--          The connection is rejected.
--  Action: Create a database link with the same name as the database it
--          connects to, or set global_names=false in init.ora, or in a
--          startup script:
--          alter session set global_names = false;
--
--  2. Check how Oracle has mapped this against the domains:
--  SQL> select owner, object_name
--    2    from sys.dba_objects
--    3   where object_type = 'DATABASE LINK'
--    4     and object_name like '%REMOTE_LINK%';
--
--  3. Perform a simple query for a quick response against the remote database:
--  SQL> select count(*)
--    2  from [remote_table]@%REMOTE_LINK%;
--
------------------------------------------------------------------------------
whenever SQLERROR exit failure
whenever OSERROR exit failure
set serveroutput on size 1000000;
set pagesize 0
set verify off
set feedback off
set pages 100

connect / as sysdba
spool tmp/%ORACLE_SID%_dblink.log

prompt Creating database link %REMOTE_LINK% to %REMOTE_DATABASE%

-- Save current DBLINK  owner password
var vcr_pwd varchar2(30);
var retcode number;
begin
  :retcode:=0;
  select password
    into :vcr_pwd
    from dba_users
   where username = '%REMOTE_LINKOWNER%';
exception
  when others then
    :retcode:=sqlcode;
    dbms_output.put_line('Could not save user %REMOTE_LINKOWNER%''s password.');
end;
/
spool off

set termout off feedback off heading off echo off linesize 1000
spool tmp/pseudo-if.sql
select '/*' from dual where :retcode=0;
spool off
@tmp/pseudo-if.sql
select 'Could not get dblink owner %REMOTE_LINKOWNER%''s hashed password.
We need to log on as this user using a temporary password to create the
dblink and then restore the password to the original.
Exiting...' from dual;
exit 1
-- */
-- We could use create or replace here but it is not compatible with 8i
spool tmp/%REMOTE_LINK%_dblink.sql
--select 'whenever SQLERROR exit failure' from dual;
select 'whenever OSERROR exit failure' from dual;
select 'drop database link %REMOTE_LINK%;' from dual;
select 'create database link %REMOTE_LINK% connect to %REMOTE_USER% identified by %REMOTE_PASSWORD% using ''%REMOTE_DATABASE%'';' from dual;
select 'exit' from dual;
spool off

-- Allow DBLINK owner to create DBLINKS
grant create database link to %REMOTE_LINKOWNER%;

-- Give temp password to DBLINK owner
alter user %REMOTE_LINKOWNER% identified by tmppwd;
! sqlplus %REMOTE_LINKOWNER%/tmppwd @tmp/%REMOTE_LINK%_dblink.sql
-- Restore password of DBLINK owner
exec execute immediate 'alter user %REMOTE_LINKOWNER% identified by values '''||:vcr_pwd||'''';

-- Revoke DBLINK owner create of DBLINKS
revoke create database link from %REMOTE_LINKOWNER%;

------------------------------------------------------------------------------
-- end of file
------------------------------------------------------------------------------
