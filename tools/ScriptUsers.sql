------------------------------------------------------------------------------
--  Header: $
------------------------------------------------------------------------------
-- ScriptUsers.sql Version 0.5
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Makes creation scripts for all the specified users
-- in the currently logged-in Oracle instance. A single file is generated,
-- called Users.sql
-- The output files can be used to create an installation of a database.
--
-- Usage:
-- ~~~~~
-- sqlplus "sys/[password]@[instance] as sysdba" @ScriptUsers.sql schemas
--   where schemas is a comma-delimited string of schemas for which scripts
--   need to be created for, e.g. billy,bubba,bobby.
--
-- Notes:
-- ~~~~~
-- The target directory must exist and correspond to the output of this
-- command in SQLPLUS:
-- SQL> show parameters UTL_FILE_DIR
-- This is set up in the file 'init.ora' for this Oracle instance, e.g:
-- UTL_FILE_DIR=/tmp. If UTL_FILE_DIR='*', then the file will be created
-- in the current directory.
--
-- Outstanding Issues:
-- ~~~~~~~~~~~~~~~~~~
-- * Table spaces are implemented exactly as they are used on the source
--   database, which may seem OK, but the usual way of specifying tablespaces
--   in installations is to use pre-defined tablespace names that are mapped
--   to tablespaces.
--
-- Further testing:
-- Verify all sorts of table against the results of 'exp'
------------------------------------------------------------------------------
-- Copyright (C) 1999-2004 Gerrit Hoekstra
-- Author: Gerrit Hoekstra <gerrit@hoekstra.co.uk>
-- Visit <www.hoekstra.co.uk/opensource> for the most recent version.
--
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details. <www.gnu.org>
--
-- If you use this program to provide publicly available output, please
-- give some form of credit in the results.  If you don't like the way the
-- script does something, or feel that you can improve it, please send a diff.
------------------------------------------------------------------------------
-- Other contributors:
-- None so far.
------------------------------------------------------------------------------
set serveroutput on size 1000000 format word_wrapped;
set echo off
set showmode off
set verify off
set linesize 120
set trim on
set tab off
whenever SQLERROR exit failure
whenever OSERROR exit failure


-- Get Parameters
column db_name new_value db_name noprint;
select sys_context('userenv','db_name') as db_name from dual;
prompt Enter the comma-delimited names of the users / schemas in the &db_name database for which
prompt User creation scripts need to be created for, e.g. UTL,CRD,DBT. Or nothing to abort.
variable tablespaces varchar2(32000);
declare
  ex_no_input exception;
  v_message   varchar2(32000);
begin
  :tablespaces:=trim(upper('&1'));
  if(:tablespaces is null)then
    dbms_output.put_line('User name not specified. Exiting...');
    raise ex_no_input;
  else
    v_message:='Building User creation scripts ['||:tablespaces||']';
    if(length(v_message)>75)then
      dbms_output.put_line(v_message);
    else
      dbms_output.put_line('+'||lpad('-',length(v_message)+2,'-')||'+');
      dbms_output.put_line('| '||v_message||' |');
      dbms_output.put_line('+'||lpad('-',length(v_message)+2,'-')||'+');
    end if;
  end if;
end;
/


declare
  -- For nice copyright notices, if you don't want to GNU-tify your resulting
  -- code, set your company / oraganisation name here:
  v_company_name constant varchar2(100) := NULL;

  v_dir             varchar2(200);    -- UTL_FILE directory
  v_start           number;           -- Start time
  v_end             number;           -- End time
  v_file_handle     utl_file.file_type;
  v_line            integer;          -- Line counter
  v_file_name       varchar2(100);    -- Table creation File name

  v_sql             varchar2(1000);   -- buffer
  v_count           integer;          -- Loop counter
  v_year            varchar2(4);      -- Copyright Year

  -- Get all schemas for which table create scripts will be created
  cursor c_schemas is
    select *
      from sys.dba_users
     where instr(upper(:schemas),username) <> 0
     order by username;

  -- Get all table spaces for the users
  cursor c_tablespaces(p_username in varchar2) is
    select tablespace_name
      from sys.dba_ts_quotas
     where username = p_username
     order by 1;

begin
  v_start:=dbms_utility.get_time;
  dbms_output.put_line('Building create script for the following users:');
  for c_s in c_schemas loop
    dbms_output.put_line(c_s.username);
  end loop;
  -- Make up file name
  v_file_name := 'users.sql';
  dbms_output.put_line('in file '||v_file_name||'.');

  -- Find which directory UTL_FILE is allowed to write to, and pick one:
  begin
    select max(value)
      into v_dir
      from sys.v_$parameter
     where upper(name) = 'UTL_FILE_DIR';
    if(v_dir='' or v_dir is null)then
      raise no_data_found;
    end if;
    -- Deal with access to all directories
    if(v_dir='*')then
      v_dir:='';
      dbms_output.put_line('Files will be built in the current directory on the Oracle Server.');
    else
      -- Deal with multiple directories:
      if(instr(v_dir,',')>0)then
        -- Choose the first directory
        v_dir:=substr(v_dir,1,instr(v_dir,',')-1);
      end if;
      dbms_output.put_line('Files will be built in directory "'||v_dir||'" on the Oracle Server.');
    end if;
  exception
    when no_data_found then
      dbms_output.put_line('Cannot create table script files.');
      dbms_output.put_line('=================================');
      dbms_output.put_line('You must specify a specific target directory for SYS.UTL_FILE');
      dbms_output.put_line('in this Oracle instance''s init.ora file, eg. UTL_FILE_DIR=/tmp');
      dbms_output.put_line('Remember to bounce the Oracle Server to effect this change to init.ora,');
      dbms_output.put_line('and if it is hosted on WIN32, to reboot the box.');
      return;
    when others then
      dbms_output.put_line('You must have SELECT rights to the SYS schema.');
      return;
  end;

  -- Copyright notice year
  select to_char(sysdate,'YYYY')
    into v_year
    from dual;

  -- Open file
  begin
       v_file_handle := utl_file.fopen(v_dir,v_file_name, 'w');
  exception
    when others then
      dbms_output.put_line('* Could not create file '||v_dir||'/'||v_file_name);
      dbms_output.put_line('* Exception ['||sqlcode||']. Message ['||sqlerrm||']');
      return;
  end;

  -- Write this table to file
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, '-- $'||'Header: $');
  if(v_company_name is not null)then
  utl_file.put_line(v_file_handle, '--      (c) Copyright '||v_year||' '||v_company_name||'.  All rights reserved.');
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--      These coded instructions, statements and computer programs contain');
  utl_file.put_line(v_file_handle, '--      unpublished information proprietary to '||v_company_name||' and are protected');
  utl_file.put_line(v_file_handle, '--      by international copyright law.  They may not be disclosed to third');
  utl_file.put_line(v_file_handle, '--      parties, copied or duplicated, in whole or in part, without the prior');
  utl_file.put_line(v_file_handle, '--      written consent of '||v_company_name||'.');
  utl_file.put_line(v_file_handle, '--');
  end if;
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, '--  DESCRIPTION:');
  utl_file.put_line(v_file_handle, '--  User creation file for database %ORACLE_SID% on %ORACLE_HOST%.');
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--  USAGE:');
  utl_file.put_line(v_file_handle, '--  $ export ORACLE_SID=%ORACLE_SID%');
  utl_file.put_line(v_file_handle, '--  $ sqlplus "sys/<password> as sysdba" install/@%ORACLE_SID%_users.sql');
  utl_file.put_line(v_file_handle, '--  This will restore all states in the application if they already exist.');
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--  ORIGIN:');
  utl_file.put_line(v_file_handle, '--  This file was originally generated by the ScriptUsers.sql utility');
  utl_file.put_line(v_file_handle, '--  from the database '||trim(sys_context('userenv','db_name'))||' on '||to_char(sysdate(),'DDMONYYYY HH24:MI:SS.'));
  utl_file.put_line(v_file_handle, '--  by user '||trim(sys_context('userenv','os_user'))||' on Oracle client '||replace(trim(sys_context('userenv','host')),chr(0),''));
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, 'whenever SQLERROR exit failure');
  utl_file.put_line(v_file_handle, 'spool log/%ORACLE_SID%_users.log');
  utl_file.put_line(v_file_handle, 'whenever OSERROR exit failure');
  utl_file.put_line(v_file_handle, 'set serveroutput on size 1000000;');
  utl_file.put_line(v_file_handle, 'set pagesize 0');
  utl_file.put_line(v_file_handle, 'set verify off');
  utl_file.put_line(v_file_handle, 'set feedback off');
  utl_file.put_line(v_file_handle, ' ');


  for c in c_schemas loop
    utl_file.put_line(v_file_handle, '-- Drop user if already exists:');
    utl_file.put_line(v_file_handle, 'declare ');
    utl_file.put_line(v_file_handle, '  v_count integer;');
    utl_file.put_line(v_file_handle, 'begin');
    utl_file.put_line(v_file_handle, '  select count(*)');
    utl_file.put_line(v_file_handle, '    into v_count');
    utl_file.put_line(v_file_handle, '    from sys.dba_users');
    utl_file.put_line(v_file_handle, '   where username = '''||c.username||''';');
    utl_file.put_line(v_file_handle, '  if(v_count>0) then');
    utl_file.put_line(v_file_handle, '    execute immediate ''drop user '||c.username||' cascade'';');
    utl_file.put_line(v_file_handle, '  end if;');
    utl_file.put_line(v_file_handle, 'end;');
    utl_file.put_line(v_file_handle, '/');
    utl_file.put_line(v_file_handle, ' ');
    utl_file.fflush(v_file_handle);
    utl_file.put_line(v_file_handle, '-- Create user:');
    utl_file.put_line(v_file_handle, 'create user '||c.username);
    utl_file.put_line(v_file_handle, '  identified by '||c.username||'ADM');
    utl_file.put_line(v_file_handle, '  default tablespace '||c.default_tablespace);
    utl_file.put_line(v_file_handle, '  temporary tablespace '||c.temporary_tablespace);
    utl_file.put_line(v_file_handle, '  profile '||c.profile);
    -- Add tablespaces
    for c_t in c_tablespaces(c.username) loop
      utl_file.put_line(v_file_handle, '  quota unlimited on '||c_t.tablespace_name);
    end loop;
    utl_file.put_line(v_file_handle, ';');
    utl_file.put_line(v_file_handle, ' ');
    utl_file.fflush(v_file_handle);
  end loop;

  utl_file.put_line(v_file_handle, 'spool off');
  utl_file.put_line(v_file_handle, 'disconnect');
  utl_file.put_line(v_file_handle, 'exit');

  -- File closing
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, '-- end of file');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.fflush(v_file_handle);
  utl_file.fclose(v_file_handle);

  -- Summary
  v_end:=dbms_utility.get_time;
  dbms_output.put_line('Created in '||(v_end-v_start)/100||' seconds.');
  return;

exception
  when others then
    dbms_output.put_line('* Exception: Error Code: ['||to_char(sqlcode)||'] Message: ['||sqlerrm||'].');
    utl_file.fflush(v_file_handle);
    utl_file.fclose(v_file_handle);
end;
/
exit;
------------------------------------------------------------------------
-- end of file
------------------------------------------------------------------------

