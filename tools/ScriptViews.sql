------------------------------------------------------------------------------
--  Header: $
------------------------------------------------------------------------------
-- ScriptViews.sql Version 0.5
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Scripts the creation scripts for all the views belonging to the defined
-- schemas in the currently logged-in Oracle instance, one file per table.
-- The output files can be used to create an installation of an Oracle 8i
-- 9i and 10g databases.
--
-- Output files will appear in the utl_file directory, if it has been set up.
-- The file name will have this format: [schema_name].Tables.[table_name].sql.
-- The following command line code will place the files in a directory tree:
-- For UNIX :
-- perl -MFile::Copy -e 'foreach(<*.sql>){chomp;my $f=$_;$f=~s/(.+)\.(.+)\.(.+\..+)/$3/;move($_,$f);mkdir(qq|$1|,0777);mkdir(qq|$1/$2|,0777);move($f,qq|$1/$2/.|);}'
-- For WIN32:
-- perl -MFile::Copy -e "foreach(<*.sql>){chomp;my $f=$_;$f=~s/(.+)\.(.+)\.(.+\..+)/$3/;move($_,$f);mkdir(qq|$1|,0777);mkdir(qq|$1/$2|,0777);move($f,qq|$1/$2/.|);}"
-- Note that existing files will be overwritten.
--
-- Usage:
-- ~~~~~
-- sqlplus "sys/[password]@[instance] as sysdba" @ScriptViews.sql schemas
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
prompt Enter the name of the schema in the &db_name database for which
prompt table scripts need to be created for, e.g. UTIL, or nothing to abort
variable schemas varchar2(100);
declare
  ex_no_input exception;
  v_message   varchar2(100);
begin
  :schemas:=trim(upper('&1'));
  if(:schemas is null)then
    dbms_output.put_line('Schema name not specified. Exiting...');
    raise ex_no_input;
  else
    v_message:='Building Views for schema(s) ['||:schemas||']';
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
  v_file_handle     utl_file.file_type;
  v_start           number;           -- Start time
  v_end             number;           -- End time
  v_line            integer;          -- Line counter

  --v_long_value      long(32760);      -- For dealing with long values
  --v_clob_value      clob;             -- For dealing with long values

  v_file_name       varchar2(100);    -- Table creation File name
  v_file_count      integer := 0;     -- File counter
  v_sql             varchar2(2000);   -- buffer
  v_count           integer;          -- Loop counter
  v_year            varchar2(4);      -- Copyright Year
  v_last_schema     sys.all_sequences.sequence_owner%type:='fish';

  -- Get all schemas for which sequence create scripts will be created
  cursor c_schemas is
    select distinct owner
      from sys.dba_views
     where instr(upper(:schemas),owner) <> 0
     order by 1;

  -- Get all required views
  cursor c_views is
    select t.owner, t.view_name, t.text_length, t.text
      from sys.dba_views t
     where instr(upper(:schemas),t.owner) <> 0
       and t.text is not null
     order by t.owner,t.view_name;

  -- Get view Grants
  cursor c_grants  (p_owner   in varchar2,
                    p_name    in varchar2) is
    select *
      from sys.dba_tab_privs
     where owner = p_owner
       and table_name = p_name
     order by privilege;

begin
  v_start:=dbms_utility.get_time;
  dbms_output.put_line('Building create scripts for all views in the following schemas:');
  for c_s in c_schemas loop
    dbms_output.put_line(c_s.owner);
  end loop;

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


  for c1 in c_views loop
    -- Make up file name
    v_file_count := v_file_count + 1;
    v_file_name := lower(c1.owner)||'.views.'||lower(c1.view_name)||'.'||'sql';
    -- Open file
    begin
      dbms_output.put_line('Building creation script for view '||c1.owner||'.'||c1.view_name||' in file '||v_file_name||'.');
      v_file_handle := utl_file.fopen(v_dir,v_file_name, 'w');
    exception
      when others then
        dbms_output.put_line('* Could not create file '||v_dir||'/'||v_file_name);
        dbms_output.put_line('* Exception ['||sqlcode||']. Message ['||sqlerrm||']');
        return;
    end;

    -- Write this table to file
    utl_file.put_line(v_file_handle,   '------------------------------------------------------------------------------');
    utl_file.put_line(v_file_handle,   '-- $'||'Header: $');
    if(v_company_name is not null)then
      utl_file.put_line(v_file_handle, '--');
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
    utl_file.put_line(v_file_handle, '--  View creation file for database %ORACLE_SID% on %ORACLE_HOST%.');
    utl_file.put_line(v_file_handle, '--');
    utl_file.put_line(v_file_handle, '--  USAGE:');
    utl_file.put_line(v_file_handle, '--  $ export ORACLE_SID=%ORACLE_SID%');
    utl_file.put_line(v_file_handle, '--  $ sqlplus "sys/<password> as sysdba" @application/'||replace(translate(v_file_name,'.','/'),'/sql','.sql'));
    utl_file.put_line(v_file_handle, '--  This will restore all states in the application if they already exist.');
    utl_file.put_line(v_file_handle, '--');
    utl_file.put_line(v_file_handle, '--  ORIGIN:');
    utl_file.put_line(v_file_handle, '--  This file was originally generated by the ScriptViews.sql utility');
    utl_file.put_line(v_file_handle, '--  from the database '||trim(sys_context('userenv','db_name'))||' on '||to_char(sysdate(),'DDMONYYYY HH24:MI:SS.'));
    utl_file.put_line(v_file_handle, '--  by user '||trim(sys_context('userenv','os_user'))||' on Oracle client '||replace(trim(sys_context('userenv','host')),chr(0),''));
    utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
    utl_file.put_line(v_file_handle, 'whenever SQLERROR exit failure');
    utl_file.put_line(v_file_handle, 'spool log/%ORACLE_SID%_views.log');
    utl_file.put_line(v_file_handle, 'whenever OSERROR exit failure');
    utl_file.put_line(v_file_handle, 'set serveroutput on size 1000000;');
    utl_file.put_line(v_file_handle, 'set pagesize 0');
    utl_file.put_line(v_file_handle, 'set verify off');
    utl_file.put_line(v_file_handle, 'set feedback off');

    utl_file.put_line(v_file_handle, '-- Drop view if it already exists');
    utl_file.put_line(v_file_handle, '-- ');
    utl_file.put_line(v_file_handle, 'prompt Creating view '||c1.owner||'.'||c1.view_name||':');
    utl_file.put_line(v_file_handle, 'declare ');
    utl_file.put_line(v_file_handle, '  v_count integer;');
    utl_file.put_line(v_file_handle, 'begin');
    utl_file.put_line(v_file_handle, '  select count(*)');
    utl_file.put_line(v_file_handle, '    into v_count');
    utl_file.put_line(v_file_handle, '    from sys.dba_views');
    utl_file.put_line(v_file_handle, '   where owner = upper('''||c1.owner||''')');
    utl_file.put_line(v_file_handle, '     and view_name  = upper('''||c1.view_name||''');');
    utl_file.put_line(v_file_handle, '  if(v_count>0) then');
    utl_file.put_line(v_file_handle, '    execute immediate ''drop view '||c1.owner||'.'||c1.view_name||''';');
    utl_file.put_line(v_file_handle, '  end if;');
    utl_file.put_line(v_file_handle, 'end;');
    utl_file.put_line(v_file_handle, '/');
    utl_file.put_line(v_file_handle, ' ');
    utl_file.fflush(v_file_handle);

    -- View
    utl_file.put_line(v_file_handle, 'create view '||c1.owner||'.'||c1.view_name||' as ');
    declare
      v_text_length     pls_integer;
      v_offset          pls_integer:=1;
      v_raw             raw(1024);
      v_linelength      pls_integer:=70;
    begin
      dbms_lob.open(c1.text,dbms_lob.lob_readonly);
      v_text_length:=dbms_lob.getlength(c1.text);
      while(v_offset<v_text_length)loop
        dbms_lob.read(c1.text,v_linelength,v_offset,v_raw);
        utl_file.put(v_file_handle, utl_raw.cast_to_varchar2(v_raw));
        v_offset:=v_offset+v_linelength;
      end loop;
      dbms_lob.close(c1.text);
      utl_file.put_line(v_file_handle,';');
      utl_file.new_line(v_file_handle);
    exception
      when others then
        dbms_output.put_line('* Trying to convert LONG to a LOB');
        dbms_output.put_line('* Exception: Error Code: ['||to_char(sqlcode)||'] Message: ['||sqlerrm||'].');
    end;

    -- Grants
    for c2 in c_grants(c1.owner,c1.view_name) loop
      v_sql := 'grant '||c2.privilege||' on '||c2.owner||'.'||c2.table_name||' to '||c2.grantee||';';
      utl_file.put_line(v_file_handle, v_sql);
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
  end loop;

  -- Summary
  v_end:=dbms_utility.get_time;
  dbms_output.put_line('Created '||v_file_count||' files in '||(v_end-v_start)/100||' seconds.');
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

