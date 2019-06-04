------------------------------------------------------------------------------
--  Header: $
------------------------------------------------------------------------------
--  ScriptPrivileges.sql Version 0.5
--  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Scripts the creation scripts for all the privileges of the defined
-- schemas in the currently logged-in Oracle instance, one file per table.
-- The output files can be used to create an installation of an Oracle 8i
-- 9i and 10g databases.
--
-- Output files will appear in the utl_file directory, if it has been defined.
-- Note that existing files will be overwritten.
--
-- Usage:
-- ~~~~~
-- sqlplus "sys/[password]@[instance] as sysdba" @ScriptPrivileges.sql schemas
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

-- Get Parameters
column db_name new_value db_name noprint;
select sys_context('userenv','db_name') as db_name from dual;
prompt Enter the name of the schema in the &db_name database for which
prompt Package scripts need to be created for, e.g. UTL, or nothing to abort
variable schemas varchar2(100);
declare
  ex_no_input exception;
  v_message   varchar2(100);
begin
  :schemas:=trim(both ',' from replace(replace(trim(upper('&1')),' '),',,',','));
  if(:schemas is null)then
    dbms_output.put_line('Schema name not specified. Exiting...');
    raise ex_no_input;
  else
    v_message:='Building Privileges for schema(s) ['||:schemas||']';
    dbms_output.put_line('+'||lpad('-',length(v_message)+2,'-')||'+');
    dbms_output.put_line('| '||v_message||' |');
    dbms_output.put_line('+'||lpad('-',length(v_message)+2,'-')||'+');
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
  v_new_priv        boolean := true;  -- One-shot
  v_last_grantee    varchar2(30);     -- One-shot

  v_sql             varchar2(1000);   -- buffer
  v_count           integer;          -- Loop counter
  v_year            varchar2(4);      -- Copyright Year

  -- Get all users for which privilege will be created
  cursor c_schemas is
    select distinct
           grantee
      from sys.dba_tab_privs
     where instr(upper(:schemas),grantee) <> 0
     union
    select distinct
           grantor
      from sys.dba_tab_privs
     where instr(upper(:schemas),grantor) <> 0
     order by 1;

  -- Get all system privileges
  cursor c_sys_privs is
    select distinct
           t1.privilege
         , t1.admin_option
         , t1.grantee
      from sys.dba_sys_privs t1
     where instr(upper(:schemas),t1.grantee)<>0
     order by t1.grantee,t1.privilege;

  -- Get all object privileges granted to specified schemas
  -- Makes: grant c.privilege on c.owner.c.table_name to c.grantee;
  cursor c_object_privs is
    select distinct
           t.grantee,
           t.privilege,
           t.owner,
           t.table_name,
           t.grantable,
           decode(o.object_type,
                  'PACKAGE','PACKAGE',
                  'PACKAGE BODY','PACKAGE',
                  o.object_type) as object_type
      from sys.dba_tab_privs t
     inner join sys.dba_objects o on o.owner = t.owner
                                 and o.object_name = t.table_name
     where instr(upper(:schemas),t.grantee)<>0
     order by 1,2,3,4,5,6;

  -- Get all object privileges owned by specified schemas to others
  cursor c_grantor_privs is
    select distinct
           t.grantee,
           t.privilege,
           t.owner,
           t.table_name,
           t.grantable,
           decode(o.object_type,
                 'PACKAGE','PACKAGE',
                 'PACKAGE BODY','PACKAGE',
                 o.object_type) as object_type
      from sys.dba_tab_privs t
     inner join sys.dba_objects o on o.owner = t.owner
                                 and o.object_name = t.table_name
     where instr(upper(:schemas),t.grantor)<>0
       and instr(upper(:schemas),t.grantee)=0
     order by 1,2,3,4,5,6;

begin
  v_start:=dbms_utility.get_time;
  dbms_output.put_line('Building create script for the following users'' privileges:');
  for c_s in c_schemas loop
    dbms_output.put_line(c_s.grantee);
  end loop;
  -- Make up file name
  v_file_name := 'privileges.sql';
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
  utl_file.put_line(v_file_handle,   '-- $'||'Header: $');
  if(v_company_name is not null)then
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--  (c) Copyright '||v_year||' '||v_company_name||'.  All rights reserved.');
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--  These coded instructions, statements and computer programs contain');
  utl_file.put_line(v_file_handle, '--  unpublished information proprietary to '||v_company_name||' and are protected');
  utl_file.put_line(v_file_handle, '--  by international copyright law.  They may not be disclosed to third');
  utl_file.put_line(v_file_handle, '--  parties, copied or duplicated, in whole or in part, without the prior');
  utl_file.put_line(v_file_handle, '--  written consent of '||v_company_name||'.');
  end if;
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, '--  DESCRIPTION:');
  utl_file.put_line(v_file_handle, '--  User priviledge configuration file for database %ORACLE_SID% on %ORACLE_HOST%.');
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--  USAGE:');
  utl_file.put_line(v_file_handle, '--  $ export ORACLE_SID=%ORACLE_SID%');
  utl_file.put_line(v_file_handle, '--  $ sqlplus "sys/<password> as sysdba" install/@%ORACLE_SID%_priviledges.sql');
  utl_file.put_line(v_file_handle, '--  This will restore all states in the application if they already exist.');
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--  ORIGIN:');
  utl_file.put_line(v_file_handle, '--  This file was originally generated by the ScriptPrivileges.sql utility');
  utl_file.put_line(v_file_handle, '--  from the database '||trim(sys_context('userenv','db_name'))||' on '||to_char(sysdate(),'DDMONYYYY HH24:MI:SS.'));
  utl_file.put_line(v_file_handle, '--  by user '||trim(sys_context('userenv','os_user'))||' on Oracle client '||replace(trim(sys_context('userenv','host')),chr(0),''));
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, 'whenever SQLERROR exit failure');
  utl_file.put_line(v_file_handle, 'spool log/%ORACLE_SID%_privileges.log');
  utl_file.put_line(v_file_handle, 'whenever OSERROR exit failure');
  utl_file.put_line(v_file_handle, 'set serveroutput on size 1000000;');
  utl_file.put_line(v_file_handle, 'set pagesize 0');
  utl_file.put_line(v_file_handle, 'set verify off');
  utl_file.put_line(v_file_handle, 'set feedback off');
  utl_file.put_line(v_file_handle, ' ');
  utl_file.put_line(v_file_handle, '--{{BEGIN AUTOGENERATED CODE}}');
  utl_file.put_line(v_file_handle, ' ');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, 'prompt SYS privileges');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, 'grant grant any privilege to SYS with admin option;');
  utl_file.put_line(v_file_handle, ' ');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, 'prompt SYSTEM Privileges');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  v_last_grantee:='@';
  for c_sp in c_sys_privs loop
    if(v_last_grantee<>c_sp.grantee)then
      v_last_grantee:=c_sp.grantee;
      utl_file.put_line(v_file_handle, ' ');
      utl_file.put_line(v_file_handle, 'prompt SYSTEM Privileges granted to '||c_sp.grantee);
    end if;
    v_sql := 'grant '||c_sp.privilege||' to '||c_sp.grantee;
    if(c_sp.admin_option='YES')then
      v_sql:=v_sql||' with admin option';
    end if;
    v_sql:=v_sql||';';
    utl_file.put_line(v_file_handle, v_sql);
  end loop;
  utl_file.put_line(v_file_handle, ' ');
  utl_file.fflush(v_file_handle);

  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, 'prompt Object Privileges');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  v_last_grantee:='@';
  for c_tp in c_object_privs loop
    if(v_last_grantee<>c_tp.grantee)then
      v_last_grantee:=c_tp.grantee;
      utl_file.put_line(v_file_handle, ' ');
      utl_file.put_line(v_file_handle, 'prompt Object Privileges granted to '||c_tp.grantee);
    end if;
    if(c_tp.object_type='DIRECTORY')then
      v_sql := 'grant '||c_tp.privilege||' on directory '||c_tp.owner||'.'||c_tp.table_name||' to '||c_tp.grantee;
    else
      v_sql := 'grant '||c_tp.privilege||' on '||c_tp.owner||'.'||c_tp.table_name||' to '||c_tp.grantee;
    end if;
    if(c_tp.grantable='YES')then
      v_sql:=v_sql||' with grant option';
    end if;
    v_sql:=v_sql||';';
    utl_file.put_line(v_file_handle, v_sql);
  end loop;
  utl_file.put_line(v_file_handle, ' ');
  utl_file.fflush(v_file_handle);

  v_last_grantee:='@';
  for c_tp in c_grantor_privs loop
    if(v_last_grantee<>c_tp.grantee)then
      v_last_grantee:=c_tp.grantee;
      utl_file.put_line(v_file_handle, ' ');
      utl_file.put_line(v_file_handle, 'prompt '||trim(',' from replace(replace(:schemas,c_tp.grantee),',,',','))||
                                       '-owned Object Privileges granted to '||c_tp.grantee);
    end if;
    if(c_tp.object_type='DIRECTORY')then
      v_sql := 'grant '||c_tp.privilege||' on directory '||c_tp.owner||'.'||c_tp.table_name||' to '||c_tp.grantee;
    else
      v_sql := 'grant '||c_tp.privilege||' on '||c_tp.owner||'.'||c_tp.table_name||' to '||c_tp.grantee;
    end if;
    if(c_tp.grantable='YES')then
      v_sql:=v_sql||' with grant option';
    end if;
    v_sql:=v_sql||';';
    utl_file.put_line(v_file_handle, v_sql);
  end loop;
  utl_file.put_line(v_file_handle, ' ');
  utl_file.put_line(v_file_handle, '--{{END AUTOGENERATED CODE}}');
  utl_file.put_line(v_file_handle, ' ');

  utl_file.put_line(v_file_handle, 'spool off');
  utl_file.put_line(v_file_handle, 'disconnect');
  utl_file.put_line(v_file_handle, 'exit');
  utl_file.fflush(v_file_handle);


  -- File closing
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, '-- end of file');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.fflush(v_file_handle);
  utl_file.fclose(v_file_handle);

  -- Summary
  v_end:=dbms_utility.get_time;
  dbms_output.put_line('Created in '||(v_end-v_start)/100||' seconds.');
  dbms_output.put_line('+----------------------------------------------------------+');
  dbms_output.put_line('| NOTE: If you are running the script manually remember to |');
  dbms_output.put_line('|       run the following commands on the database server: |');
  dbms_output.put_line('+----------------------------------------------------------+');
  dbms_output.put_line('$ cd '||v_dir);
  dbms_output.put_line('$ mkdir -p install');
  dbms_output.put_line('$ mv '||v_file_name||' install/.');
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

