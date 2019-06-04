------------------------------------------------------------------------------
--  Header: $
------------------------------------------------------------------------------
-- ScriptPackages.sql Version 0.5
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Scripts the creation scripts for all the packages belonging to the defined
-- schemas in the currently logged-in Oracle instance, one file per table.
-- The output files can be used to create an installation of an Oracle 8i
-- 9i and 10g databases.
--
-- Output files will appear in the utl_file directory, if it has been defined.
-- The file name will have this format: [schema_name].packages.[package_name].pl?.
--
-- Usage:
-- ~~~~~
-- sqlplus -s "sys/[password]@[instance] as sysdba" @ScriptPackages.sql schemas
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
prompt Enter the comma-delimited names of the schemas in the &db_name database for which
prompt Package scripts need to be created for, e.g. UTL,CRD,DBT. Or nothing to abort.
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
    v_message:='Building Packages for schema(s) ['||:schemas||']';
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
  v_dir             varchar2(200);    -- UTL_FILE directory
  v_start           number;           -- Start time
  v_end             number;           -- End time

  v_file_handle     utl_file.file_type;
  v_line            integer;          -- Line counter
  v_wrapped         integer;          -- package wrap status
  v_file_name       varchar2(100);    -- Package File name
  v_file_count      integer := 0;
  v_text            sys.all_source.text%type;
  v_pos             integer;
  v_create_done     pls_integer;

  -- Get all schemas for which packages create scripts will be created
  cursor c_schemas is
    select distinct owner
      from sys.all_objects
     where instr(upper(:schemas),owner) <> 0
       and (object_type = 'PACKAGE' or object_type = 'PACKAGE BODY')
     order by 1;

  -- Get all user-written unwrapped packages
  cursor c_packages is
    select distinct o.owner, o.object_name, o.object_type
      from sys.all_objects o
     where (o.object_type = 'PACKAGE' or o.object_type = 'PACKAGE BODY')
       and instr(upper(:schemas),o.owner) <> 0
     order by 1,2,3;

  -- Get all source code for each package
  cursor c_source(p_owner   in varchar2,
                  p_package in varchar2,
                  p_type    in varchar2) is
    select s.text
      from all_source s
     where s.name = upper(p_package)
       and s.owner= upper(p_owner)
       and s.type = upper(p_type)
     order by line;

begin
  v_start:=dbms_utility.get_time;
  dbms_output.put_line('Building create scripts for all packages in the following schemas:');
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
      dbms_output.put_line('Cannot create package script files.');
      dbms_output.put_line('===================================');
      dbms_output.put_line('You must specify a specific target directory for SYS.UTL_FILE');
      dbms_output.put_line('in this Oracle instance''s init.ora file, eg. UTL_FILE_DIR=/tmp');
      dbms_output.put_line('Remember to bounce the Oracle Server to effect this change to init.ora,');
      dbms_output.put_line('and if it is hosted on WIN32, to reboot the box.');
      return;
    when others then
      dbms_output.put_line('You must have SELECT rights to the SYS schema.');
      return;
  end;

  for c in c_packages loop
    -- Check if the package is wrapped
    select count(*)
      into v_wrapped
      from all_source s
     where (s.text like '%'||lower(c.object_name)||' wrapped%'
        or s.text like '/* Source is wrapped */' )
       and s.name  = c.object_name
       and s.type  = c.object_type
       and s.owner = c.owner;

    if(v_wrapped=0)then
      -- Package is not wrapped, so build create script for it:
      -- Make up file name
      v_file_count := v_file_count + 1;
      if(c.object_type='PACKAGE') then
        v_file_name := lower(c.owner)||'.packages.'||lower(c.object_name)||'.'||'plh';   -- Package header
      else
        v_file_name := lower(c.owner)||'.packages.'||lower(c.object_name)||'.'||'plb';   -- Package body
      end if;

      -- Open file
      begin
        dbms_output.put_line('Building creation script for '||c.owner||'.'||c.object_name||' '||lower(c.object_type)||' in file '||v_file_name||':');
        v_file_handle := utl_file.fopen(location => v_dir,
                                        filename => v_file_name,
                                        open_mode => 'w',
                                        max_linesize  => 32767);
      exception
        when others then
          dbms_output.put_line('* Could not create file '||v_dir||'/'||v_file_name);
          dbms_output.put_line('* Exception ['||sqlcode||']. Message ['||sqlerrm||']');
          return;
      end;

      -- Write to file
      v_line := 0;
      v_create_done:=0; -- Create statement completed
      for c2 in c_source(c.owner,c.object_name,c.object_type) loop
        v_line := v_line + 1;
        v_text:=c2.text;
        --v_text := substr(c2.text,1,length(c2.text)-1);  -- Strip trailing NewLine char
        -- Keep a watch for pathological packages
        --if(length(v_text)>250)then
        --  v_text:='*** LINE TOO LONG ****'; -- This surely will cause a compilation error ;-)
        --end if;

        if(v_line=1)then
          -- First line always contains 'package'/'package body' or 'package <spaces><name>'/'package body <spaces><name>'
          -- The package name is wherever it was left in the original code but with the schema name replaced with spaces (why?).
          -- Turn this into 'CREATE OR REPLACE PACKAGE/PACKAGE BODY' and reconstruct the fully-qualified
          -- package name.
          v_text:='create or replace '||v_text;
        end if;

        if(v_create_done=0)then
          -- Look for package name and add schema name
          v_pos:=instr(lower(v_text),lower(c.object_name),-1);
          if(v_pos > 0)then
            -- Must not be in a commented section
            -- (crude and incomplete check - should parse for / * ... * / style comments as well)
            if(instr(substr(v_text,1,v_pos),'--')=0)then
              v_text:=substr(v_text,1,v_pos-1)||' '||lower(c.owner)||'.'||substr(v_text,v_pos);
              while(length(replace(v_text,'  ',' '))<length(v_text))loop
                v_text:=replace(v_text,'  ',' ');
              end loop;
              v_text:=trim(v_text);
              v_create_done:=1;
            end if;
          end if;
        end if;

        utl_file.put(v_file_handle, v_text);
        -- Force occasional buffer flushes as utl_file struggles with large file creation
        if(mod(v_line,100)=0)then
          utl_file.fflush(file => v_file_handle);
        end if;
      end loop;
      utl_file.put_line(v_file_handle,' ');
      utl_file.put_line(v_file_handle,'/');
      utl_file.fclose(file => v_file_handle);
      dbms_output.put_line(v_line||' lines');
    else
      dbms_output.put_line('Ignore '||c.object_type||' '||c.object_name||' as it is wrapped.');
    end if;
  end loop;
  -- Summary
  v_end:=dbms_utility.get_time;
  dbms_output.put_line('Created '||v_file_count||' files in '||(v_end-v_start)/100||' seconds.');
  return;
exception
  when utl_file.invalid_path then
    raise_application_error(-20001,'INVALID_PATH: File location or filename was invalid.');
  when utl_file.invalid_mode then
    raise_application_error(-20002,'INVALID_MODE: The open_mode parameter in FOPEN was invalid.');
  when utl_file.invalid_filehandle then
    raise_application_error(-20002,'INVALID_FILEHANDLE: The file handle was invalid.');
  when utl_file.invalid_operation then
    raise_application_error(-20003,'INVALID_OPERATION: The file could not be opened or operated on as requested.');
  when utl_file.read_error then
    raise_application_error(-20004,'READ_ERROR: An operating system error occurred during the read operation.');
  when utl_file.write_error then
    raise_application_error(-20005,'WRITE_ERROR: An operating system error occurred during the write operation.');
  when utl_file.internal_error then
    raise_application_error(-20006,'INTERNAL_ERROR: An unspecified error in PL/SQL.');
  when others then
    dbms_output.put_line(v_line||':'||v_text);
    dbms_output.put_line('* Exception: Error Code: ['||to_char(sqlcode)||'] Message: ['||sqlerrm||'].');
end;
/

declare
  -- For nice copyright notices, if you don't want to GNU-tify your resulting
  -- code, set your company / oraganisation name here:
  v_company_name constant varchar2(100) := NULL;

  v_dir             varchar2(200);    -- UTL_FILE directory
  v_start           number;           -- Start time
  v_end             number;           -- End time
  v_year            varchar2(4);      -- Copyright Year
  v_file_name       varchar2(100):='packages.sql';
  v_file_handle     utl_file.file_type;

  -- Get all schemas for which packages create scripts will be created
  cursor c_schemas is
    select distinct owner
      from sys.dba_objects
     where instr(upper(:schemas),owner) <> 0
       and (object_type = 'PACKAGE' or object_type = 'PACKAGE BODY')
     order by 1;

  -- Get all user-written unwrapped packages
  cursor c_packages is
    select distinct o.owner, o.object_name, o.object_type
      from sys.dba_objects o
     where (o.object_type = 'PACKAGE' or o.object_type = 'PACKAGE BODY')
       and instr(upper(:schemas),o.owner) <> 0
     order by 1,2,3;

begin
  v_start:=dbms_utility.get_time;
  dbms_output.put_line('Building package installation script for all packages in the following schemas:');
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
      dbms_output.put_line('Cannot create package script files.');
      dbms_output.put_line('===================================');
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
    v_file_handle := utl_file.fopen(location => v_dir,
                                    filename => v_file_name,
                                    open_mode => 'w',
                                    max_linesize  => 32767);
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
  utl_file.put_line(v_file_handle, '--  Package installation file for database %ORACLE_SID% on %ORACLE_HOST%.');
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--  USAGE:');
  utl_file.put_line(v_file_handle, '--  $ export ORACLE_SID=%ORACLE_SID%');
  utl_file.put_line(v_file_handle, '--  $ sqlplus "sys/<password> as sysdba" install/@%ORACLE_SID%_packages.sql');
  utl_file.put_line(v_file_handle, '--  This will restore all states in the application if they already exist.');
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--  ORIGIN:');
  utl_file.put_line(v_file_handle, '--  This file was originally generated by the ScriptPackages.sql utility');
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
  utl_file.put_line(v_file_handle, 'prompt Package Headers:');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, ' ');
  for c in c_packages loop
    if(c.object_type='PACKAGE')then
      utl_file.put_line(v_file_handle, 'prompt '||lower(c.owner)||'.'||lower(c.object_name));
      utl_file.put_line(v_file_handle, '@%INSTALLATION_HOME%/application/'||lower(c.owner)||'/packages/'||lower(c.object_name)||'.plh');
    end if;
  end loop;
  utl_file.put_line(v_file_handle, ' ');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, 'prompt Package Bodies:');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, ' ');
  for c in c_packages loop
    if(c.object_type='PACKAGE BODY')then
      utl_file.put_line(v_file_handle, 'prompt '||lower(c.owner)||'.'||lower(c.object_name));
      utl_file.put_line(v_file_handle, '@%INSTALLATION_HOME%/application/'||lower(c.owner)||'/packages/'||lower(c.object_name)||'.plb');
    end if;
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
  dbms_output.put_line('$ ls *.pl? | perl -nle ''$f=$_;$f=~s/(.+)\.(.+)\.(.+\..+)/$3/; \');
  dbms_output.put_line('> `mv $_ $f; mkdir -p application/$1/$2; mv $f application/$1/$2/.`;''');
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

