------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- ScriptTables.sql Version 0.5
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Scripts the creation scripts for all the tables belonging to the defined
-- schemas in the currently logged-in Oracle instance, one file per table.
-- The output files can be used to create an installation of an Oracle 8i,
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
-- sqlplus "sys/[password]@[instance] as sysdba" @ScriptTables.sql schemas
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
-- * Even though partitioned tables are dealt with, other forms of
--   table constructions are not yet dealt with.
-- * Temporary tables are assumed to be global. This is not always the case.
-- * Table spaces are implemented exactly as they are used on the source
--   database. The tables space names will not necessarily have the same name
--   on the target database when this script is subsequently run on it.
--   One way is around this is to substitute the tablespace names with SQL
--   "defines" after running this script by doing a global search-and-replace.
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
prompt table scripts need to be created for, e.g. UTL, or nothing to abort
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
    v_message:='Building Tables for schema(s) ['||:schemas||']';
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
  v_file_count      integer := 0;     -- File counter

  v_long_value      long(32760);      -- For dealing with long values
  v_last_constraint varchar2(100);    -- One shot flag
  v_sql             varchar2(1000);   -- buffer
  v_count           integer;          -- Loop counter
  v_initrans        integer;          -- physical_attributes_clause
  v_object_count    integer;          -- Object counter
  v_year            varchar2(4);      -- Copyright Year
  v_tab_partitions  sys.all_tab_partitions%rowtype;

  v_fk_owner        sys.all_constraints.owner%type;
  v_fk_table_name   sys.all_constraints.table_name%type;
  v_r_constraint_name sys.all_constraints.r_constraint_name%type;
  v_index_tablespace sys.all_indexes.tablespace_name%type;
  v_comment         varchar2(4000);   -- Table and column comment

  -- Get all schemas for which table create scripts will be created
  cursor c_schemas is
    select distinct owner
      from sys.all_tables
     where instr(upper(:schemas),owner) <> 0
       and table_name <> 'PLAN_TABLE'
       and table_name not like '%$%'
       and table_name not like '%/%'
       and table_name not like '%_IOT_%'
     order by 1;

  -- Get all required tables
  cursor c_tables is
    select distinct t.*
      from sys.all_tables t
     where instr(upper(:schemas),t.owner) <> 0
       and t.table_name <> 'PLAN_TABLE'
       and t.table_name not like '%$%'
       and t.table_name not like '%/%'
       and table_name not like '%_IOT_%'
     order by t.owner,t.table_name;

  -- Get all columns for each table
  cursor c_columns(p_owner   in varchar2,
                   p_table   in varchar2) is
    select *
      from sys.all_tab_columns c
     where c.table_name = upper(p_table)
       and c.owner= upper(p_owner)
     order by c.owner,c.table_name,c.column_id;

  -- Get the partitioned details for each table
  cursor c_partitions(p_owner  in varchar2,
                      p_table  in varchar2) is
    select distinct
           t.partitioning_type    as partitioning_type,
           t.def_tablespace_name  as def_tablespace_name,
           c.column_name          as column_name,
           p.partition_name       as partition_name,
           t.subpartitioning_type as subpartition_type
      from sys.all_part_tables         t
         , sys.all_part_key_columns    c
         , sys.all_part_col_statistics p
     where t.owner      = c.owner
       and t.table_name = c.name
       and t.owner      = p.owner
       and t.table_name = p.table_name(+)
       and t.owner      = p_owner(+)
       and t.table_name = p_table
       and rtrim(c.object_type) = 'TABLE'
     order by p.partition_name;

  -- Get the user-generated constraints for a table
  cursor c_constraints (p_owner  in varchar2,
                        p_table  in varchar2) is
    select *
      from sys.all_constraints t
     where t.owner = p_owner
       and t.table_name = p_table
       and t.generated = 'USER NAME'
     order by t.constraint_type, t.constraint_name;

  -- Get the columns of a constraint
  cursor c_cons_columns (p_owner  in varchar2,
                         p_table  in varchar2,
                         p_cons   in varchar2) is
    select *
      from sys.all_cons_columns
     where owner = p_owner
       and table_name = p_table
       and constraint_name = p_cons
     order by position;

  -- Get the referenced key columns of a constraint
  cursor c_ref_key_columns (p_cons   in varchar2) is
    select *
      from sys.all_cons_columns
     where constraint_name = p_cons
     order by position;

  -- Get Indexes that are not already used as primary and unique constraints
  cursor c_table_indexes  (p_owner  in varchar2,
                           p_table  in varchar2) is
    select i.*
      from sys.all_indexes i
     where table_owner = p_owner
       and table_name  = p_table
       and i.index_name not in
            (select t.constraint_name from sys.all_constraints t)
            -- If it was already used for the constraints, ignore it
     order by index_name;

  -- Get Index Partitions
  cursor c_indexes_part   (p_index  in varchar2) is
    select *
      from sys.all_ind_partitions
     where index_name = p_index
     order by partition_position;

  -- Get index columns
  cursor c_index_cols (p_owner  in varchar2,
                       p_table  in varchar2,
                       p_index  in varchar2) is
    select *
      from sys.all_ind_columns
     where table_owner = p_owner
       and table_name = p_table
       and index_name = p_index
     order by column_position;

  -- Get Table Grantees
  cursor c_grantees (p_owner  in varchar2,
                     p_table  in varchar2) is
    select GRANTEE
         , count(*) as grant_count
      from sys.all_tab_privs
     where table_schema = p_owner
       and table_name = p_table
     group by GRANTEE
     order by 1;

  -- Get Table Grants
  cursor c_grants  (p_owner   in varchar2,
                    p_table   in varchar2,
                    p_grantee in varchar2) is
    select *
      from sys.all_tab_privs
     where grantee      = p_grantee
       and table_schema = p_owner
       and table_name   = p_table
     order by privilege;

begin
  v_start:=dbms_utility.get_time;
  dbms_output.put_line('Building create scripts for all tables in the following schemas:');
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

  for c in c_tables loop
    -- Make up file name
    v_file_count := v_file_count + 1;
    v_file_name := lower(c.owner)||'.tables.'||lower(c.table_name)||'.'||'sql';
    -- Open file
    begin
      dbms_output.put_line('Building creation script for table '||c.owner||'.'||c.table_name||' in file '||v_file_name||'.');
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
    end if;
    utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
    utl_file.put_line(v_file_handle, '--  DESCRIPTION:');
    utl_file.put_line(v_file_handle, '--  Table creation file for database %ORACLE_SID% on %ORACLE_HOST%.');
    utl_file.put_line(v_file_handle, '--');
    utl_file.put_line(v_file_handle, '--  USAGE:');
    utl_file.put_line(v_file_handle, '--  $ export ORACLE_SID=%ORACLE_SID%');
    utl_file.put_line(v_file_handle, '--  $ sqlplus "sys/<password> as sysdba" @application/'||replace(translate(v_file_name,'.','/'),'/sql','.sql'));
    utl_file.put_line(v_file_handle, '--  This will restore all states in the application if they already exist.');
    utl_file.put_line(v_file_handle, '--');
    utl_file.put_line(v_file_handle, '--  ORIGIN:');
    utl_file.put_line(v_file_handle, '--  This file was originally generated by the ScriptTables.sql utility');
    utl_file.put_line(v_file_handle, '--  from the database '||trim(sys_context('userenv','db_name'))||' on '||to_char(sysdate(),'DDMONYYYY HH24:MI:SS.'));
    utl_file.put_line(v_file_handle, '--  by user '||trim(sys_context('userenv','os_user'))||' on Oracle client '||replace(trim(sys_context('userenv','host')),chr(0),''));
    utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
    utl_file.put_line(v_file_handle, 'whenever SQLERROR exit failure');
    utl_file.put_line(v_file_handle, 'spool log/%ORACLE_SID%_tables.log');
    utl_file.put_line(v_file_handle, 'whenever OSERROR exit failure');
    utl_file.put_line(v_file_handle, 'set serveroutput on size 1000000;');
    utl_file.put_line(v_file_handle, 'set pagesize 0');
    utl_file.put_line(v_file_handle, 'set verify off');
    utl_file.put_line(v_file_handle, 'set feedback off');
    utl_file.put_line(v_file_handle, ' ');

    utl_file.put_line(v_file_handle, 'prompt Creating table '||c.owner||'.'||c.table_name||':');
    utl_file.put_line(v_file_handle, '-- Drop table if it already exists');
    utl_file.put_line(v_file_handle, '-- Note that the contents of the table will also be deleted');
    utl_file.put_line(v_file_handle, 'declare ');
    utl_file.put_line(v_file_handle, '  v_count integer:=0;');
    utl_file.put_line(v_file_handle, 'begin');
    utl_file.put_line(v_file_handle, '  select count(*)');
    utl_file.put_line(v_file_handle, '    into v_count');
    utl_file.put_line(v_file_handle, '    from sys.all_objects');
    utl_file.put_line(v_file_handle, '   where object_type = ''TABLE''');
    utl_file.put_line(v_file_handle, '     and owner = '''||c.owner||'''');
    utl_file.put_line(v_file_handle, '     and object_name = '''||c.table_name||''';');
    utl_file.put_line(v_file_handle, '  if(v_count>0) then');
    utl_file.put_line(v_file_handle, '    execute immediate ''drop table '||c.owner||'.'||c.table_name||' cascade constraints'';');
    utl_file.put_line(v_file_handle, '  end if;');
    utl_file.put_line(v_file_handle, 'end;');
    utl_file.put_line(v_file_handle, '/');
    utl_file.put_line(v_file_handle, ' ');
    utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
    utl_file.put_line(v_file_handle, '-- Create table');
    utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
    utl_file.fflush(v_file_handle);

    -- Basic Table creation
    -- ~~~~~~~~~~~~~~~~~~~~
    if(c.temporary='Y')then
      utl_file.put_line(v_file_handle, 'create global temporary table '||c.owner||'.'||c.table_name);
    else
      utl_file.put_line(v_file_handle, 'create table '||c.owner||'.'||c.table_name);
    end if;
    utl_file.put_line(v_file_handle, '(');
    -- Get all table columns
    v_line := 0;
    for c2 in c_columns(c.owner,c.table_name) loop
      v_line := v_line + 1;
      if(v_line>1)then
        v_sql := ', ';
      else
        v_sql := '  ';
      end if;
      v_sql:=v_sql||rpad(c2.column_name,31,' ')||rpad(c2.data_type,10,' ');
      if(c2.data_precision is null)then
        -- Only show precision for non-binary and non-date
        if(instr('DATE,CLOB,LOB,NCLOB,RAW,LONG,BFILE,ROWID',c2.data_type)=0) then
          v_sql := v_sql||'('||c2.data_length||')';
        end if;
      else
        -- Ignore precision specs and allow default
        if(c2.data_scale is not null)then
          v_sql := v_sql||'('||c2.data_precision||','||nvl(c2.data_scale,0)||')';
        end if;
      end if;
      -- Default column value
      -- You have to copy it into an intermediate value
      v_long_value := c2.data_default;
      if(v_long_value is not null)then
        v_sql := v_sql||' default '||v_long_value;
      end if;
      -- Nullability
      if(c2.nullable='N')then
        v_sql := v_sql||' not null';
      end if;
      utl_file.put_line(v_file_handle, v_sql);
    end loop;
    utl_file.put_line(v_file_handle, ')');
    utl_file.fflush(v_file_handle);

    -- Do table space, partitioning etc..
    if(c.temporary='Y')then
      -- Finish off temporary table
      -- Note that we can not determine from the sys tables what type of commit
      -- clause was used, so assume 'on commit delete rows'
      utl_file.put_line(v_file_handle, 'on commit delete rows;');
    else
      -- Tablespace clause
      if(c.tablespace_name is not null)then
        utl_file.put_line(v_file_handle, 'tablespace "'||c.tablespace_name||'"');
      end if;

      -- Physical attributes clause
      if(c.pct_free is not null)then
        utl_file.put_line(v_file_handle, 'pctfree '||to_char(c.pct_free));
      end if;
      if(c.pct_used is not null)then
        utl_file.put_line(v_file_handle, 'pctused '||to_char(c.pct_used ));
      end if;
      if(c.ini_trans is not null)then
        utl_file.put_line(v_file_handle, 'initrans '||to_char(c.ini_trans));
      end if;
      if(c.max_trans is not null)then
        utl_file.put_line(v_file_handle, 'maxtrans '||to_char(c.max_trans));
      end if;

      -- Table STORAGE clause
      if((c.INITIAL_EXTENT is not null) or
         (c.NEXT_EXTENT    is not null) or
         (c.MIN_EXTENTS    is not null) or
         (c.MAX_EXTENTS    is not null) or
         (c.PCT_INCREASE   is not null)) then
        utl_file.put_line(v_file_handle,   'storage(');
        if(c.INITIAL_EXTENT is not null)then
          utl_file.put_line(v_file_handle, '  initial '||to_char(c.INITIAL_EXTENT/1024)||'K');
        end if;
        if(c.NEXT_EXTENT is not null)then
          utl_file.put_line(v_file_handle, '  next '||to_char(c.NEXT_EXTENT/1024)||'K');
        end if;
        if(c.MIN_EXTENTS is null)then
          utl_file.put_line(v_file_handle, '  minextents 1');
        else
          utl_file.put_line(v_file_handle, '  minextents '||to_char(c.MIN_EXTENTS));
        end if;
        if(c.MAX_EXTENTS=2147483645 or c.MAX_EXTENTS is null)then
          utl_file.put_line(v_file_handle, '  maxextents unlimited');
        else
          utl_file.put_line(v_file_handle, '  maxextents '||to_char(c.MAX_EXTENTS));
        end if;
        if(c.PCT_INCREASE is null)then
          utl_file.put_line(v_file_handle, '  pctincrease 0');
        else
          utl_file.put_line(v_file_handle, '  pctincrease '||to_char(c.PCT_INCREASE));
        end if;
        utl_file.put_line(v_file_handle,   ')');
      end if;
      utl_file.fflush(v_file_handle);

      -- Partitioning clauses
      if(c.partitioned='YES')then
        v_count := 0;
        -- TODO: Deal with sub partitions
        for c3 in c_partitions(c.owner,c.table_name) loop
          v_count := v_count + 1;
          if(v_count=1)then
            utl_file.put_line(v_file_handle, '  partition by '||c3.partitioning_type||' ('||c3.column_name||') (');
            v_sql := '    partition ';
          else
            v_sql := '  , partition ';
          end if;
          -- Get the high_value for the partition
          select high_value
            into v_long_value
            from sys.all_tab_partitions
           where table_name = c.table_name
             and table_owner= c.owner
             and partition_name = c3.partition_name;
          v_sql := v_sql ||'"'||c3.partition_name||'" values less than ('||v_long_value||')';
          utl_file.put_line(v_file_handle, v_sql);
          -- Get Tablespace, physical and storage attributes clause
          begin
            select *
              into v_tab_partitions
              from sys.all_tab_partitions
             where table_owner    = c.owner
               and table_name     = c.table_name
               and partition_name = c3.partition_name;
             -- Tablespace clause
            if(v_tab_partitions.tablespace_name is not null)then
              utl_file.put_line(v_file_handle, '      tablespace "'||v_tab_partitions.tablespace_name||'"');
            end if;
            -- Physical attributes clause
            if(v_tab_partitions.pct_free is not null)then
              utl_file.put_line(v_file_handle,  '      pctfree  '||to_char(v_tab_partitions.pct_free));
            end if;
            if(v_tab_partitions.pct_used is not null)then
              utl_file.put_line(v_file_handle,  '      pctused  '||to_char(v_tab_partitions.pct_used ));
            end if;
            if(v_tab_partitions.ini_trans is not null)then
              utl_file.put_line(v_file_handle,  '      initrans '||to_char(v_tab_partitions.ini_trans));
            end if;
            if(v_tab_partitions.max_trans is not null)then
              utl_file.put_line(v_file_handle,  '      maxtrans '||to_char(v_tab_partitions.max_trans));
            end if;

            -- Storage attributes clause
            if((v_tab_partitions.INITIAL_EXTENT is not null) or
               (v_tab_partitions.NEXT_EXTENT    is not null) or
               (v_tab_partitions.MIN_EXTENT     is not null) or
               (v_tab_partitions.MAX_EXTENT     is not null) or
               (v_tab_partitions.PCT_INCREASE   is not null)) then
              utl_file.put_line(v_file_handle,   '      storage ');
              utl_file.put_line(v_file_handle,   '      (');
              if(v_tab_partitions.INITIAL_EXTENT is not null)then
                utl_file.put_line(v_file_handle, '        initial '||to_char(v_tab_partitions.INITIAL_EXTENT/1024)||'K');
              end if;
              if(v_tab_partitions.NEXT_EXTENT is not null)then
                utl_file.put_line(v_file_handle, '        next '||to_char(v_tab_partitions.NEXT_EXTENT/1024)||'K');
              end if;
              if(v_tab_partitions.MIN_EXTENT is null)then
                utl_file.put_line(v_file_handle, '        minextents 1');
              else
                utl_file.put_line(v_file_handle, '        minextents '||to_char(v_tab_partitions.MIN_EXTENT));
              end if;
              if(v_tab_partitions.MAX_EXTENT=2147483645 or v_tab_partitions.MAX_EXTENT is null)then
                utl_file.put_line(v_file_handle, '        maxextents unlimited');
              else
                utl_file.put_line(v_file_handle, '        maxextents '||to_char(v_tab_partitions.MAX_EXTENT));
              end if;
              if(v_tab_partitions.PCT_INCREASE is null)then
                utl_file.put_line(v_file_handle, '        pctincrease 0');
              else
                utl_file.put_line(v_file_handle, '        pctincrease '||to_char(v_tab_partitions.PCT_INCREASE));
              end if;
              if(v_tab_partitions.FREELISTS=0 or v_tab_partitions.FREELISTS is null)then
                utl_file.put_line(v_file_handle, '        freelists 1');
              else
                utl_file.put_line(v_file_handle, '        freelists '||to_char(v_tab_partitions.FREELISTS));
              end if;
              if(v_tab_partitions.FREELIST_GROUPS=0 or v_tab_partitions.FREELIST_GROUPS is null)then
                utl_file.put_line(v_file_handle, '        freelist groups 1');
              else
                utl_file.put_line(v_file_handle, '        freelist groups '||to_char(v_tab_partitions.FREELIST_GROUPS));
              end if;
              if(v_tab_partitions.BUFFER_POOL is null)then
                utl_file.put_line(v_file_handle, '        buffer pool default');
              else
                utl_file.put_line(v_file_handle, '        buffer pool '||v_tab_partitions.BUFFER_POOL);
              end if;
              utl_file.put_line(v_file_handle,   '      )');
            end if;
            utl_file.fflush(v_file_handle);

          exception
            when others then
              -- No partition data or too much partition data
              -- Use table's tablespace clause
              if(c3.def_tablespace_name is not null)then
                utl_file.put_line(v_file_handle, '  tablespace "'||c3.def_tablespace_name||'"');
              end if;
          end;
        end loop;
        utl_file.put_line(v_file_handle, '  )');
      end if;
      utl_file.fflush(v_file_handle);

      -- Table Cache
      if(c.cache='Y')then
        utl_file.put_line(v_file_handle, '  cache');
      end if;
      -- Table Logging
      if(c.logging is not null)then
        if(c.logging='YES')then
          utl_file.put_line(v_file_handle, '  logging');
        else
          utl_file.put_line(v_file_handle, '  nologging');
        end if;
      end if;
      -- Table Degree of parallelism
      if(c.degree is not null)then
        if(ltrim(c.degree)='0')then
          utl_file.put_line(v_file_handle, '  noparallel');
        elsif(ltrim(c.degree)='1')then
          utl_file.put_line(v_file_handle, '  parallel');
        else
          utl_file.put_line(v_file_handle, '  parallel (');
          utl_file.put_line(v_file_handle, '    degree '||ltrim(c.degree));
          utl_file.put_line(v_file_handle, '    instances '||ltrim(c.instances));
          utl_file.put_line(v_file_handle, '  )');
        end if;
      end if;
      utl_file.put_line(v_file_handle, ';');
    end if;
    utl_file.fflush(v_file_handle);

    -- Table Comments
    -- ~~~~~~~~~~~~~~
    -- Create the following SQL:
    -- comment on table [SCHEMA].[TABLE] is
    --  '[Description]';
    select count(*)
      into v_count
      from sys.all_tab_comments
     where owner = c.owner
       and table_name = c.table_name
       and comments is not null;
    if(v_count>0)then
      select comments
        into v_comment
        from sys.all_tab_comments
       where owner = c.owner
         and table_name = c.table_name;
      utl_file.put_line(v_file_handle, ' ');
      utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
      utl_file.put_line(v_file_handle, '-- Add comments to the table');
      utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
      utl_file.put_line(v_file_handle, 'comment on table '||c.owner||'.'||c.table_name||' is');
      utl_file.put_line(v_file_handle, '  '''||v_comment||''';');
    end if;

    -- Table column Comments
    -- ~~~~~~~~~~~~~~~~~~~~~
    -- Create the following SQL:
    -- comment on column [SCHEMA].[TABLE].[COLUMN] is
    --  '[Description]';
    select count(*)
      into v_count
      from sys.all_col_comments
     where owner = c.owner
       and table_name = c.table_name
       and comments is not null;
    if(v_count>0)then
      utl_file.put_line(v_file_handle, ' ');
      utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
      utl_file.put_line(v_file_handle, '-- Add comments to the columns');
      utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
      for c14 in c_columns(c.owner,c.table_name)loop
        begin
          select comments
            into v_comment
            from sys.all_col_comments
           where owner = c.owner
             and table_name = c.table_name
             and column_name = c14.column_name;
          utl_file.put_line(v_file_handle, 'comment on column '||c.owner||'.'||c.table_name||'.'||c14.column_name||' is');
          utl_file.put_line(v_file_handle, '  '''||v_comment||''';');
        exception
          when others then
            -- No comments for this column
            null;
        end;
      end loop;
    end if;

    -- All constraints
    -- ~~~~~~~~~~~~~~~
    v_last_constraint := 'fish';
    for c4 in c_constraints(c.owner,c.table_name) loop
      -- Print section heading
      if(v_last_constraint<>c4.constraint_type)then
        v_last_constraint:=c4.constraint_type;
        utl_file.put_line(v_file_handle,   ' ');
        utl_file.put_line(v_file_handle,   '------------------------------------------------------------------------------');
        if(c4.constraint_type='P')then
          utl_file.put_line(v_file_handle, '-- Create/Recreate primary key constraints');
        elsif(c4.constraint_type='U')then
          utl_file.put_line(v_file_handle, '-- Create/Recreate unique key constraints');
        elsif(c4.constraint_type='C')then
          utl_file.put_line(v_file_handle, '-- Create/Recreate check constraints');
        elsif(c4.constraint_type='R')then
          utl_file.put_line(v_file_handle, '-- Create/Recreate foreign constraints');
        end if;
        utl_file.put_line(v_file_handle,   '------------------------------------------------------------------------------');
      end if;

      utl_file.put_line(v_file_handle, 'alter table '||c.owner||'.'||c.table_name);
      -- (Note: Do not include the schema in the constraint name)
      v_sql := '  add constraint '||c4.constraint_name;
      utl_file.put_line(v_file_handle, v_sql);
      if(c4.constraint_type='P')then
        v_sql := '  primary key (';
      elsif(c4.constraint_type='U')then
        v_sql := '  unique (';
      elsif(c4.constraint_type='C')then
        v_sql := '  check (';
      elsif(c4.constraint_type='R')then
        v_sql := '  foreign key (';
      end if;

      -- -- Get constraint columns
      if(c4.constraint_type='C')then
        -- Get Check constraint columns
        -- Special case for check constraint - all the columns
        -- are already in the LONG-type search_condition column
        v_long_value := c4.search_condition;
        v_sql:=v_sql||v_long_value;
      else
        -- Get Primary and Foreign Unique constraint columns
        v_count := 0;
        for c5 in c_cons_columns(c.owner,c.table_name,c4.constraint_name) loop
          v_count:=v_count+1;
          if(v_count>1)then
            v_sql:=v_sql||',';
          end if;
          v_sql := v_sql||c5.column_name;
        end loop;
      end if;
      utl_file.put_line(v_file_handle, v_sql||')');
      -- Specfy which indexes to use for primary and unique constrains
      if(c4.constraint_type='P' or c4.constraint_type='U')then
        utl_file.put_line(v_file_handle, '  using index');
      end if;
      -- Specify which tables reference foreign constraint
      if(c4.constraint_type='R')then
        -- Get foreign Table details
        -- There can be only one such foreign table for this constraint
        select t.r_constraint_name
          into v_r_constraint_name
          from sys.all_constraints t
         where t.constraint_name = c4.constraint_name;
        v_sql:='  references ';
        v_count := 0;
        for c_ref_cols in c_ref_key_columns(v_r_constraint_name) loop
          v_count:=v_count+1;
          if(v_count=1)then
            -- First column in referenced key
            v_sql:=v_sql||c_ref_cols.owner||'.'||c_ref_cols.table_name||'('||c_ref_cols.column_name;
          else
            v_sql:=v_sql||','||c_ref_cols.column_name;
          end if;
        end loop;
        v_sql:=v_sql||')';
        utl_file.put_line(v_file_handle, v_sql);
      end if;

      -- Continue with partitioning information for primary or unique constraints
      if(c.partitioned='YES' and (c4.constraint_type='P' or c4.constraint_type='U'))then
        -- Partitinioned index
        utl_file.put_line(v_file_handle, '  local');
        utl_file.put_line(v_file_handle, '  (');
        v_count := 0;
        -- TODO: Deal with sub-partitions
        for c6 in c_partitions(c.owner,c.table_name) loop
          v_count := v_count + 1;
          if(v_count>1)then
            v_sql := '  , partition ';
          else
            v_sql := '    partition ';
          end if;
          v_sql := v_sql||c6.partition_name||' tablespace '||c6.def_tablespace_name;
          utl_file.put_line(v_file_handle, v_sql);
        end loop;
        v_sql:='  ';
      else
        -- Non-Partitinioned index
        if(c4.constraint_type='P' or c4.constraint_type='U')then
          -- Get the tablespace name for this index
          begin
            select tablespace_name
              into v_index_tablespace
              from sys.all_indexes
             where owner = c.owner
               and table_name=c.table_name
               and trim(upper(index_name))=trim(upper(c4.constraint_name));
          exception
            when others then
              -- Could not get tablespace name for contraint - use that of the table as a last resort
              v_index_tablespace:=c.tablespace_name;
          end;
          utl_file.put_line(v_file_handle, '  tablespace "'||v_index_tablespace||'"');
          -- Percent Free
          utl_file.put_line(v_file_handle, '  pctfree  '||to_char(c.pct_free));
          -- The minimum and default INITRANS value for a cluster or index is 2.
          v_initrans:=c.ini_trans;
          if(v_initrans=1)then
            v_initrans:=2;
          end if;
          utl_file.put_line(v_file_handle, '  initrans '||to_char(v_initrans));
          utl_file.put_line(v_file_handle, '  maxtrans '||to_char(c.max_trans));
        end if;
      end if;

      if(c4.constraint_type='P' or c4.constraint_type='U')then
        if((c.INITIAL_EXTENT is not null) or (c.NEXT_EXTENT is not null) or (c.MIN_EXTENTS is not null) or
           (c.MAX_EXTENTS    is not null) or c.PCT_INCREASE is not null) then
          utl_file.put_line(v_file_handle,   '  storage ');
          utl_file.put_line(v_file_handle,   '  (');
          if(c.INITIAL_EXTENT is not null)then
            utl_file.put_line(v_file_handle, '    initial '||to_char(c.INITIAL_EXTENT/1024)||'K');
          end if;
          if(c.NEXT_EXTENT is not null)then
            utl_file.put_line(v_file_handle, '    next '||to_char(c.NEXT_EXTENT/1024)||'K');
          end if;
          if(c.MIN_EXTENTS is null)then
            utl_file.put_line(v_file_handle, '    minextents 1');
          else
            utl_file.put_line(v_file_handle, '    minextents '||to_char(c.MIN_EXTENTS));
          end if;
          if(c.MAX_EXTENTS=2147483645 or c.MAX_EXTENTS is null)then
            utl_file.put_line(v_file_handle, '    maxextents unlimited');
          else
            utl_file.put_line(v_file_handle, '    maxextents '||to_char(c.MAX_EXTENTS));
          end if;
          if(c.PCT_INCREASE is null)then
            utl_file.put_line(v_file_handle, '    pctincrease 0');
          else
            utl_file.put_line(v_file_handle, '    pctincrease '||to_char(c.PCT_INCREASE));
          end if;
          utl_file.put_line(v_file_handle,   '  )');
        end if;
        utl_file.put_line(v_file_handle, ';');
      elsif(c4.constraint_type='R')then
        utl_file.put_line(v_file_handle, ';');
      else
        utl_file.put_line(v_file_handle, '  '||c4.status||';');
      end if;

      utl_file.fflush(v_file_handle);
    end loop;

    -- Indexes
    -- ~~~~~~~
    -- Outline statement:
    --  create unique index [index_owner].[index_name] on [table_owner].[table_name]([col1,col2..])
    --        tablespace "[tablespace_name]"
    --        pctfree  [x]
    --        initrans [y]
    --        maxtrans [z]
    --        storage
    --        (
    --          initial [a]K
    --          minextents [b]
    --          maxextents unlimited
    --          pctincrease [c]
    --        )
    --    parallel
    --    logging
    --  ;
    v_object_count:=0;
    for c7 in c_table_indexes(c.owner,c.table_name) loop
      v_object_count:=v_object_count+1;
      if(v_object_count=1)then
        utl_file.put_line(v_file_handle,   ' ');
        utl_file.put_line(v_file_handle,   '------------------------------------------------------------------------------');
        utl_file.put_line(v_file_handle,   '-- Create/Recreate indexes ');
        utl_file.put_line(v_file_handle,   '------------------------------------------------------------------------------');
      end if;
      v_sql := 'create ';
      if(c7.uniqueness='UNIQUE')then
        v_sql:=v_sql||'unique ';
      end if;
      if(ltrim(c7.index_type)<>'NORMAL')then
        v_sql := v_sql||ltrim(c7.index_type)||' ';
      end if;
      v_sql :=v_sql||'index '||c7.owner||'.'||c7.index_name;
      utl_file.put_line(v_file_handle, v_sql);
      v_sql:='  on '||c7.table_owner||'.'||c7.table_name||'(';
      -- Get index columns
      -- e.g. create index SCOTT.IX_EMP_ADDRESS on SCOTT.EMP(ADDRESS)
      v_count := 0;
      for c8 in c_index_cols(c.owner,c.table_name,c7.index_name) loop
        v_count := v_count + 1;
        if(v_count>1)then
          v_sql:=v_sql||',';
        end if;
        v_sql:=v_sql||c8.column_name;
      end loop;
      v_sql:=v_sql||')';
      utl_file.put_line(v_file_handle, v_sql);

      -- Tablespace clause
      if(c7.tablespace_name is not null)then
        utl_file.put_line(v_file_handle,  '      tablespace "'||c7.tablespace_name||'"');
      end if;
      -- Physical attributes clause
      if(c7.pct_free is not null)then
        utl_file.put_line(v_file_handle,  '      pctfree  '||to_char(c7.pct_free));
      end if;
      if(c7.ini_trans is not null)then
        utl_file.put_line(v_file_handle,  '      initrans '||to_char(c7.ini_trans));
      end if;
      if(c7.max_trans is not null)then
        utl_file.put_line(v_file_handle,  '      maxtrans '||to_char(c7.max_trans));
      end if;

      -- Index Storage attributes clause
      if((c7.INITIAL_EXTENT is not null) or
         (c7.NEXT_EXTENT    is not null) or
         (c7.MIN_EXTENTS    is not null) or
         (c7.MAX_EXTENTS    is not null) or
         (c7.PCT_INCREASE   is not null)) then
        utl_file.put_line(v_file_handle,   '      storage ');
        utl_file.put_line(v_file_handle,   '      (');
        if(c7.INITIAL_EXTENT is not null)then
          utl_file.put_line(v_file_handle, '        initial '||to_char(c7.INITIAL_EXTENT/1024)||'K');
        end if;
        if(c7.NEXT_EXTENT is not null)then
          utl_file.put_line(v_file_handle, '        next '||to_char(c7.NEXT_EXTENT/1024)||'K');
        end if;
        if(c7.MIN_EXTENTS is null)then
          utl_file.put_line(v_file_handle, '        minextents 1');
        else
          utl_file.put_line(v_file_handle, '        minextents '||to_char(c7.MIN_EXTENTS));
        end if;
        if(c7.MAX_EXTENTS=2147483645 or c7.MAX_EXTENTS is null)then
          utl_file.put_line(v_file_handle, '        maxextents unlimited');
        else
          utl_file.put_line(v_file_handle, '        maxextents '||to_char(c7.MAX_EXTENTS));
        end if;
        if(c7.PCT_INCREASE is null)then
          utl_file.put_line(v_file_handle, '        pctincrease 0');
        else
          utl_file.put_line(v_file_handle, '        pctincrease '||to_char(c7.PCT_INCREASE));
        end if;
        utl_file.put_line(v_file_handle,   '      )');
      end if;

      -- Index on partitioned table
      if(c.partitioned='YES')then
        -- Partitioned index
        utl_file.put_line(v_file_handle, '  local');
        utl_file.put_line(v_file_handle, '  (');
        v_count := 0;
        v_sql := 'spam';
        for c9 in c_indexes_part(c7.index_name) loop
          v_count := v_count + 1;
          if(v_count=1)then
            v_sql := '    ';
          else
            v_sql := '  , ';
          end if;
          v_sql := v_sql||'partition "'||c9.partition_name||'" tablespace "'||c9.tablespace_name||'" ';
          -- Index Partition Logging clause
          if(c9.logging is not null)then
            if(c.logging='YES')then
              v_sql := v_sql||'logging';
            else
              v_sql := v_sql||'nologging';
            end if;
          end if;
          utl_file.put_line(v_file_handle, v_sql);
        end loop;
        utl_file.put_line(v_file_handle, '  )');
        utl_file.fflush(v_file_handle);
      end if;

      -- Index Parallel clause -- add instance parameter in here as well
      if(ltrim(c.degree)='0')then
        utl_file.put_line(v_file_handle, '  noparallel');
      elsif(ltrim(c.degree)='1')then
        utl_file.put_line(v_file_handle, '  parallel');
      else
        utl_file.put_line(v_file_handle, '  parallel (');
        utl_file.put_line(v_file_handle, '    degree '||ltrim(c.degree));
        utl_file.put_line(v_file_handle, '    instances '||ltrim(c.instances));
        utl_file.put_line(v_file_handle, '  )');
      end if;
      -- Index Logging clause
      if(c.logging is not null)then
        if(c.logging='YES')then
          utl_file.put_line(v_file_handle, '  logging');
        else
          utl_file.put_line(v_file_handle, '  nologging');
        end if;
      end if;
      utl_file.put_line(v_file_handle, ';');
      utl_file.fflush(v_file_handle);
    end loop;

    -- Table Priviledges
    -- ~~~~~~~~~~~~~~~~~
    v_object_count:=0;
    for c8 in c_grantees(c.owner,c.table_name) loop
      v_object_count:=v_object_count+1;
      if(v_object_count=1)then
        utl_file.put_line(v_file_handle,   ' ');
        utl_file.put_line(v_file_handle,   '------------------------------------------------------------------------------');
        utl_file.put_line(v_file_handle,   '-- Grant/Revoke privileges');
        utl_file.put_line(v_file_handle,   '------------------------------------------------------------------------------');
      end if;
      if(c8.grant_count>=7)then
        -- Full house: we can say "grant all"
        v_sql := 'grant all';
      else
        -- Show selection of grant for this grantee
        v_count := 0;
        v_sql := 'grant ';
        for c9 in c_grants(c.owner,c.table_name,c8.grantee) loop
          v_count:=v_count+1;
          if(v_count>1)then
            v_sql:=v_sql||', ';
          end if;
          v_sql:=v_sql||c9.privilege;
        end loop;
      end if;
      v_sql:=v_sql||' on '||c.owner||'.'||c.table_name||' to '||c8.grantee||';';
      utl_file.put_line(v_file_handle, v_sql);
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


declare
  -- For nice copyright notices, if you don't want to GNU-tify your resulting
  -- code, set your company / oraganisation name here:
  v_company_name constant varchar2(100) := NULL;

  v_dir             varchar2(200);    -- UTL_FILE directory
  v_start           number;           -- Start time
  v_end             number;           -- End time
  v_year            varchar2(4);      -- Copyright Year
  v_file_name       varchar2(100):='tables.sql';
  v_file_handle     utl_file.file_type;

  -- Get all schemas for which packages create scripts will be created
  cursor c_schemas is
    select distinct owner
      from sys.all_tables
     where instr(upper(:schemas),owner) <> 0
       and table_name <> 'PLAN_TABLE'
       and table_name not like '%$%'
       and table_name not like '%/%'
       and table_name not like '%_IOT_%'
     order by 1;

  -- Get all required tables
  cursor c_tables is
    select distinct t.*
      from sys.all_tables t
     where instr(upper(:schemas),t.owner) <> 0
       and t.table_name <> 'PLAN_TABLE'
       and t.table_name not like '%$%'
       and t.table_name not like '%/%'
       and table_name not like '%_IOT_%'
     order by t.owner,t.table_name;

begin
  v_start:=dbms_utility.get_time;
  dbms_output.put_line('Building table installation script for all tables in the following schemas:');
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
      dbms_output.put_line('Cannot create table installation file.');
      dbms_output.put_line('======================================');
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
  utl_file.put_line(v_file_handle, '--  $'||'Header: $');
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
  utl_file.put_line(v_file_handle, '--  Table installation file for database %ORACLE_SID% on %ORACLE_HOST%.');
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--  USAGE:');
  utl_file.put_line(v_file_handle, '--  $ export ORACLE_SID=%ORACLE_SID%');
  utl_file.put_line(v_file_handle, '--  $ sqlplus "sys/<password> as sysdba" install/@%ORACLE_SID%_tables.sql');
  utl_file.put_line(v_file_handle, '--  This will restore all states in the application if they already exist.');
  utl_file.put_line(v_file_handle, '--');
  utl_file.put_line(v_file_handle, '--  ORIGIN:');
  utl_file.put_line(v_file_handle, '--  This file was originally generated by the ScriptTables.sql utility');
  utl_file.put_line(v_file_handle, '--  from the database '||trim(sys_context('userenv','db_name'))||' on '||to_char(sysdate(),'DDMONYYYY HH24:MI:SS.'));
  utl_file.put_line(v_file_handle, '--  by user '||trim(sys_context('userenv','os_user'))||' on Oracle client '||replace(trim(sys_context('userenv','host')),chr(0),''));
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, 'whenever SQLERROR exit failure');
  utl_file.put_line(v_file_handle, 'spool log/%ORACLE_SID%_tables.log');
  utl_file.put_line(v_file_handle, 'whenever OSERROR exit failure');
  utl_file.put_line(v_file_handle, 'set serveroutput on size 1000000;');
  utl_file.put_line(v_file_handle, 'set pagesize 0');
  utl_file.put_line(v_file_handle, 'set verify off');
  utl_file.put_line(v_file_handle, 'set feedback off');
  utl_file.put_line(v_file_handle, ' ');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, 'prompt Installing Tables:');
  utl_file.put_line(v_file_handle, '------------------------------------------------------------------------------');
  utl_file.put_line(v_file_handle, ' ');
  utl_file.put_line(v_file_handle, '--{{BEGIN AUTOGENERATED CODE}}');
  utl_file.put_line(v_file_handle, ' ');
  for c in c_tables loop
    utl_file.put_line(v_file_handle, '@%INSTALLATION_HOME%/application/'||lower(c.owner)||'/tables/'||lower(c.table_name)||'.sql');
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
  dbms_output.put_line('$ ls *.sql | perl -nle ''$f=$_;$f=~s/(.+)\.(.+)\.(.+\..+)/$3/; \');
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

