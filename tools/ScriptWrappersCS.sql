------------------------------------------------------------------------------
--  Header: $
------------------------------------------------------------------------------
-- ScriptWrappersXX.sql Version 0.1
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Scripts wrapper code for all the stored procedures belonging to the schemas
-- indicated. The output file can be compiled into a middleware or client-side
-- project, and will appear in the utl_file directory, if it has been set up.
-- The file name will have this format: [schema_name].XX, where XX indicates
-- the programming language that the wrapper is coded in:
--
-- CS:    C-Sharp using ADO.Net and the Oracle driver
-- PL:    Perl using DBI
-- CPP:   C++ using ADO 2.1
-- KSH:   Korn Shell using sqlplus
-- JAVA:  Java using JDBC
--
-- This will run on Oracle 9, 10g ..., bit not on 8i and lower, because the
-- behaviour of the case statement is inconsistent on 8i --.
-- Also, Regular Expressions are not supported before 9i.
--
-- Note that the existing files in the target directory will be overwritten.
--
-- Object-oriented languages will create a class for each schema,
-- with a method for every stored procedure call. All the classes will be
-- namespaced with the name OracleWrapper.
--
-- Conventions when developing stored procedures:
-- 1. Functions return an integer, which normally indicates if the process
--    executed successfully or not (0=success, negative=failure).
--    The errors can be looked up in the Error manual, or using the command:
--    $ oerr ora <error_code>
-- 2. Interface descriptions to the stored procedures are assumed to be in
--    the package specification. Any descriptions in the source code will
--    not be included.
-- 3. The interface descriptions are assumed to immediately preceed the
--    interface definition with no separation lines between.
-- 4. For now, assume that the interface to all overridden stored procedures
--    are more or less the same so that the comment of the first proc can be
--    be used for all of them.
--
-- Usage:
-- ~~~~~
-- sqlplus -s "sys/[password]@[instance] as sysdba" @ScriptWrappersXX.sql schemas
--   where schemas is a comma-delimited string of schemas for which scripts
--   need to be created for, e.g. billy,bubba,bobby.
--
-- Assumptions about SQL Programming Style:
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- The following assumptions had to be made about the style in which stored
-- procedures are coded in Oracle PL/SQL, and are loosly based on the most
-- commonly used styles. The assumptions are few and any freeform style will
-- therefore probably work with this wrapper. Note that this is NOT critical
-- although it does allow the PL/SQL procedure comments to also appear in the
-- wrapper code. Most target environments (Java/C# etc..) can use this code
-- for autodocumenting the code.
-- 1. Declarations must be on one line: function|procedure <name> etc...
-- 2. Comments should immediately precede the declaration
-- 3. Only comments from the package headers will be used.
-- 4. Comments are line-based and not of the  /*...*/ -type.
--
-- Usage of the resulting wrapper code:
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- A connection needs to be established before a wrapper method is invoked,
-- and is then passed to the class constructor (one class per schema).
-- Invoke the methods in the schema class instance and populate the parameter values.
-- Where return parameters are returned, check the value as it normally contains
-- the returning error code.
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
-- 1. Deal with wrapper code in other languages and interfaces.
-- 2. Deal with custom DB-datatypes / Compounded data type
-- 3. Create parameters externally, so that overloaded functions can be better be
--    dealt with by languages that allow overloading
-- 4. Still not an ideal way to capture stored procedure comment text when there
--    are numerous overrides to the same proc.
-- 5. Deal with SQL and PL/SQL record types. Ideally construct a class / struct
--    for each record type in another piece of Wrapper code. The problem is
--    how to retrieve the record structure from Oracle, as it is not in the
--    data dictionary. Perhaps the way forward is to insist that record parameters
--    in stored procedures are actual Oracle compuunded types that can be
--    obtained from the data dictionary?
-- 6. Default values cannnot be retrieved from the ALL_ARGUMENTS.DEFAULT_VALUE
--    column, and this Oracle bug (discovered in 1993) will not even be fixed for
--    Oracle 10g. So the only way is to parse the source code. Not easy when
--    there are overrides to contend with. Any brave volunteers?
-- 7. Refactor using a temporary lookup table instead of massive case statements
------------------------------------------------------------------------------
-- Copyright (C) 1999-2004 Gerrit Hoekstra. Alle Rechte vorbehalten.
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
prompt Wrapper scripts need to be created for, e.g. UTL,CRD,DBT. Or nothing to abort.
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
    v_message:='Building C# store procedure Wrapper functions for schema(s) ['||:schemas||']';
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
  -- {{ CONFIGURATION SECTION
  -- For nice copyright notices, if you don't want to GNU-tify your resulting
  -- code, set your company / oraganisation name here:
  v_company_name constant varchar2(100) := NULL;

  -- Preferred name for the return parameter
  v_ret_param_name  constant varchar2(20):= 'P_RET_CODE';

  -- Optimal size for return character strings
  -- This is necessary as an OracleDbType.Varchar2 Parameters needs to know this in advance
  v_out_string_size constant pls_integer:=250;

  -- Maximum number of comment lines likely to precede the function or procedure declaration
  v_max_comment_lines constant pls_integer:=20;

  -- }}

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
  v_arg_count       integer;          -- Argument counter
  v_out_arg_count   integer;          -- OUT Argument counter
  v_initrans        integer;          -- physical_attributes_clause
  v_object_count    integer;          -- Object counter
  v_year            varchar2(4);      -- Copyright Year
  v_mw_data_type    varchar2(50);     -- Middleware Data type
  v_lang_data_type  varchar2(50);     -- Specific Language Data type
  v_first           boolean:=false;   -- Done at least once
  v_namespace_name  varchar2(60);     -- Namespace name
  v_class_name      varchar2(60);     -- Class name
  v_proc_name       varchar2(60);     -- Procedure name
  v_arg_name        varchar2(60);     -- Procedure Argument name
  v_proc_line       number;           -- Source code line in procedure
  v_override_count  number;           -- Number of overrides of a store procedure
  v_pos             number;           -- List pointer
  v_last_pos        number;           -- List pointer place holder
  v_comments        dbms_sql.varchar2s;
  v_lang_data_types dbms_sql.varchar2s; -- List of language parameters type

  -- Get all schemas for which table create scripts will be created
  cursor c_schemas is
    select distinct owner
      from sys.dba_procedures t
     where instr(upper(:schemas),owner) <> 0
     order by 1;

  -- Get all package names in the schemas
  cursor c_packages(p_owner in varchar2) is
    select distinct t.object_name
      from sys.dba_procedures t
     where t.owner=p_owner
       and procedure_name is not null     -- Prevent any functions and procedures not in packages from being included
     order by t.object_name;

  -- Get all function- and procedure details for each package
  -- Need to refer to the ALL_ARGUMENTS view as functions and procedures
  -- can be overloaded, and is only indicated in this view.
  -- Keep object_names in orderin which they were programmed, so no "ORDER BY" clause.
  cursor c_procs(p_owner         in varchar2,
                 p_package_name  in varchar2) is
    select distinct owner,package_name,object_name,nvl(overload,1) overload
      from sys.all_arguments
     where package_name = upper(p_package_name)
       and owner=upper(p_owner);

  -- Get parameters / arguments for a procedure
  -- ( Note that default values are not indicated in the default column.
  --   Need to parse source code to get null values. )
  -- Use Data Level to determine the construction of compounded data types
  cursor c_params(p_owner        in varchar2,
                  p_package_name in varchar2,
                  p_proc_name    in varchar2,
                  p_overload     in number
                  ) is
    select *
      from sys.all_arguments
     where owner=p_owner
       and object_name  = p_proc_name
       and package_name = p_package_name
       and nvl(overload,1) = p_overload
     order by sequence, position;

  -- Get line number that procedure actually is declared in package spec.
  -- This cursor should only return one record per procedure declaration.
  cursor c_proc_comment(p_owner    in varchar2,
                  p_package_name in varchar2,
                  p_proc_name    in varchar2
                  ) is
    select *
      from sys.all_source
     where owner = p_owner
       and name  = p_package_name
       and type  = 'PACKAGE'
       and regexp_instr(text,'^ *(function|procedure) *'||p_proc_name||' *(\(|$)',1,1,0,'i') > 0 -- look for proc definition
       and regexp_instr(text,'^ *--')=0   -- ignore comments which may have examples of functions in them
     order by line;

begin
  v_start:=dbms_utility.get_time;
  dbms_output.put_line('Building stored procedure wrappers for all packages in the following schemas:');
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
      dbms_output.put_line('Cannot create wrapper script files.');
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

  -- Get Schemas
  for c1 in c_schemas loop
    -- Make up file name
    v_file_count := v_file_count + 1;
    v_file_name := replace(initcap(replace(c1.owner,'2','2_')),'_')||'.cs';
    -- Open file
    begin
      dbms_output.put_line('Building wrapper code for schema '||c1.owner||' in file '||v_file_name||'.');
      v_file_handle := utl_file.fopen(v_dir,v_file_name, 'w');
    exception
      when others then
        dbms_output.put_line('* Could not create file '||v_dir||'/'||v_file_name);
        dbms_output.put_line('* Exception ['||sqlcode||']. Message ['||sqlerrm||']');
        return;
    end;
    -- Write this table to file
    utl_file.put_line(v_file_handle,     '//----------------------------------------------------------------------------');
    utl_file.put_line(v_file_handle,     '//  $'||'Header: $');
    if(v_company_name is not null)then
      utl_file.put_line(v_file_handle,   '//');
      utl_file.put_line(v_file_handle,   '//  (c) Copyright '||v_year||' '||v_company_name||'.  All rights reserved.');
      utl_file.put_line(v_file_handle,   '//');
      utl_file.put_line(v_file_handle,   '//  These coded instructions, statements and computer programs contain');
      utl_file.put_line(v_file_handle,   '//  unpublished information proprietary to '||v_company_name||' and are protected');
      utl_file.put_line(v_file_handle,   '//  by international copyright law.  They may not be disclosed to third');
      utl_file.put_line(v_file_handle,   '//  parties, copied or duplicated, in whole or in part, without the prior');
      utl_file.put_line(v_file_handle,   '//  written consent of '||v_company_name||'.');
      utl_file.put_line(v_file_handle,   '//');
    end if;
    utl_file.put_line(v_file_handle,     '//----------------------------------------------------------------------------');
    utl_file.put_line(v_file_handle,     '//  DESCRIPTION:');
    utl_file.put_line(v_file_handle,     '//  Stored Procedure Wrapper code.');
    utl_file.put_line(v_file_handle,     '//');
    utl_file.put_line(v_file_handle,     '//  USAGE:');
    utl_file.put_line(v_file_handle,     '//  Compile this file in with your middleware or client application.');
    utl_file.put_line(v_file_handle,     '//');
    utl_file.put_line(v_file_handle,     '//  ORIGIN:');
    utl_file.put_line(v_file_handle,     '//  This file was originally generated by the ScriptWrappersXX.sql utility');
    utl_file.put_line(v_file_handle,     '//  from the database '||upper(trim(sys_context('userenv','db_name')))||' on '||to_char(sysdate(),'DDMONYYYY HH24:MI:SS.'));
    utl_file.put_line(v_file_handle,     '//  by user '||trim(sys_context('userenv','os_user'))||' on Oracle client '||replace(trim(sys_context('userenv','host')),chr(0),''));
    utl_file.put_line(v_file_handle,     '//  ');
    utl_file.put_line(v_file_handle,     '//  CREATION:');
    utl_file.put_line(v_file_handle,     '//  This file was created as follows:');
    utl_file.put_line(v_file_handle,     '//  sqlplus "sys/[passwd]@'||upper(trim(sys_context('userenv','db_name')))||' as sysdba" @ScriptWrappersXX.sql '||c1.owner);
    utl_file.put_line(v_file_handle,     '//----------------------------------------------------------------------------');
    utl_file.put_line(v_file_handle,     '// DO NOT EDIT THIS FILE! (unless you *really* have to)');
    utl_file.put_line(v_file_handle,     '//----------------------------------------------------------------------------');
    utl_file.put_line(v_file_handle,     ' ');
    utl_file.put_line(v_file_handle,     'using System;');
    utl_file.put_line(v_file_handle,     'using System.Data;');
    utl_file.put_line(v_file_handle,     'using System.Data.SqlTypes;');
    utl_file.put_line(v_file_handle,     'using System.Xml;');
    utl_file.put_line(v_file_handle,     'using Oracle.DataAccess.Client;');
    utl_file.put_line(v_file_handle,     'using Oracle.DataAccess.Types;');
    utl_file.put_line(v_file_handle,     ' ');
    utl_file.put_line(v_file_handle,     'namespace OracleWrapper{');
    v_namespace_name:=replace(initcap(replace(c1.owner,'2','2_')),'_');
    utl_file.put_line(v_file_handle,     '  namespace '||v_namespace_name||'{');
    -- Get Packages
    for c2 in c_packages(c1.owner) loop
      v_class_name:=replace(initcap(replace(c2.object_name,'2','2_')),'_');
      -- There is a wee problem with the MS Visual Studio when creating XML Documentation, so a little mis-use of tags here...
      utl_file.put_line(v_file_handle,   '  ');
      utl_file.put_line(v_file_handle,   '    #region Oracle package '||c1.owner||'.'||c2.object_name||' class definition');
      utl_file.put_line(v_file_handle,   '    ///<summary>');
      utl_file.put_line(v_file_handle,   '    /// Stored Procedure Wrapper code for schema '||c1.owner||'.'||c2.object_name||'<br/>');
      utl_file.put_line(v_file_handle,   '    ///<example>How to use this class:<br/><code>');
      utl_file.put_line(v_file_handle,   '    /// OracleConnection con = new OracleConnection();<br/>');
      utl_file.put_line(v_file_handle,   '    /// con.ConnectionString = "User Id=[user];Password=[password];Data Source=[database]";<br/>');
      utl_file.put_line(v_file_handle,   '    /// con.Open();<br/>');
      utl_file.put_line(v_file_handle,   '    /// '||v_class_name||' _'||v_class_name||' = new '||v_class_name||'(con);<br/>');
      utl_file.put_line(v_file_handle,   '    /// SqlInt64 p_ret_code = new SqlInt64();<br/>');
      utl_file.put_line(v_file_handle,   '    /// SqlInt64 p_int_id = new SqlInt64(1);<br/>');
      utl_file.put_line(v_file_handle,   '    /// OracleRefCursor rc = null;<br/>');
      utl_file.put_line(v_file_handle,   '    /// try{<br/>');
      utl_file.put_line(v_file_handle,   '    ///   int result = _'||v_class_name||'.GetByIntId(ref rc, p_int_id);<br/>');
      utl_file.put_line(v_file_handle,   '    ///   if(p_ret_code!=0){<br/>');
      utl_file.put_line(v_file_handle,   '    ///     throw Oracle.DataAccess.Client.OracleException(result);<br/>');
      utl_file.put_line(v_file_handle,   '    ///   }<br/>');
      utl_file.put_line(v_file_handle,   '    ///   OracleDataReader dr=rc.GetDataReader();<br/>');
      utl_file.put_line(v_file_handle,   '    ///   while(dr.Read()){<br/>');
      utl_file.put_line(v_file_handle,   '    ///     Console.WriteLine(dr.GetOracleValue(0));<br/>');
      utl_file.put_line(v_file_handle,   '    ///   }<br/>');
      utl_file.put_line(v_file_handle,   '    /// }catch(Oracle.DataAccess.Client.OracleException e){<br/>');
      utl_file.put_line(v_file_handle,   '    ///   Console.WriteLine("Failed to execute Oracle stored procedure ['||c1.owner||'.'||c2.object_name||'.GetByIntId]: " + e.Message);<br/>');
      utl_file.put_line(v_file_handle,   '    /// }<br/>');
      utl_file.put_line(v_file_handle,   '    /// </code></example></summary>');
      utl_file.put_line(v_file_handle,   '    public class '||v_class_name||'{');
      utl_file.put_line(v_file_handle,   '      ///<summary>');
      utl_file.put_line(v_file_handle,   '      /// Constructor - pass an opened ADO.Net Connection object');
      utl_file.put_line(v_file_handle,   '      ///</summary>');
      utl_file.put_line(v_file_handle,   '      public '||v_class_name||'(OracleConnection con){');
      utl_file.put_line(v_file_handle,   '        cmd=new OracleCommand();');
      utl_file.put_line(v_file_handle,   '        cmd.Connection = con;');
      utl_file.put_line(v_file_handle,   '      }');
      utl_file.put_line(v_file_handle,   '      ///<summary>');
      utl_file.put_line(v_file_handle,   '      /// ADO.Net Command object');
      utl_file.put_line(v_file_handle,   '      ///</summary>');
      utl_file.put_line(v_file_handle,   '      private OracleCommand cmd;');


      -- Get Procedures and Functions
      for c3 in c_procs(c1.owner,c2.object_name)loop

        -- Make up procedure comment extracted from the source code.
        -- Get line in source code where this procedure is.
        -- We use the comments from the first of a number of overridden stored procedures,
        -- and in some cases this will not be a perfect match
        utl_file.put_line(v_file_handle,     '      ///<summary>');
        v_override_count:=0;
        v_proc_line:=0;
        -- Get the first line of overridden procedure and only use those comments for all overrides.
        -- This is the likely approach followed by the stored procedure developer in any case.
        for c5 in c_proc_comment(c1.owner,c2.object_name,c3.object_name) loop
          if(v_override_count=0)then
            v_proc_line:=c5.line;
          end if;
          v_override_count:=v_override_count+1;
        end loop;
        if(v_override_count>0)then
          -- We have at least one overridden procedure:
          -- Get the preceding v_max_comment_lines lines
          begin
            select trim(text)
              bulk collect
              into v_comments
              from sys.all_source
             where owner = c1.owner
               and name  = c2.object_name
               and type  = 'PACKAGE'
               and line < v_proc_line
               and line >= (v_proc_line-v_max_comment_lines)
               and line >= 1
               --and regexp_instr(text,'^ *--')>0       -- only comment lines
               and regexp_instr(text,'(-|=|~){20}')=0 -- ignore lines that are separators
             order by line asc;
          exception
            when others then
              null;
          end;
          -- Managed to get some comments - find last line and work backwards
          v_pos:=v_comments.last;
          while(v_pos is not null)loop
            exit when substr(v_comments(v_pos),1,2)<>'--';
            v_last_pos:=v_pos;
            v_pos:=v_comments.prior(v_pos);
          end loop;
          -- Output comments from where we left off
          v_pos:=v_last_pos;
          while(v_pos is not null)loop
            utl_file.put_line(v_file_handle, '      ///  '||substr(substr(v_comments(v_pos),1,length(v_comments(v_pos))-1),3)||'<br/>');
            v_pos:=v_comments.next(v_pos);
          end loop;
        end if;

        -- Overloaded
        -- TODO: Display the total number of overloaded methods before the first method
        if(c3.overload>1)then
          utl_file.put_line(v_file_handle,   '      ///<overloads>Method overload '||c3.overload||'</overloads>');
        end if;

        utl_file.put_line(v_file_handle,     '      ///</summary>');

        -- Display the list of parameters and their direction
        for c6 in c_params(c3.owner,c3.package_name,c3.object_name,c3.overload)loop
          if(c6.data_level=0)then
            utl_file.put_line(v_file_handle,   '      ///<param name="'||lower(nvl(c6.argument_name,v_ret_param_name))||'">'||c6.in_out||' '||c6.data_type||'</param>');
          end if;
        end loop;
        utl_file.put_line(v_file_handle,     '      ///<returns>Returns zero on success, Oracle Error code on Failure.</returns>');

        -- Make up function header
        v_proc_name:=c3.object_name;
        v_proc_name:=replace(initcap(replace(v_proc_name,'2','2_')),'_');
        v_sql:='      public int '||v_proc_name||'(';
        utl_file.put_line(v_file_handle, v_sql);
        v_first:=true;
        v_pos:=0;
        for c4 in c_params(c3.owner,c3.package_name,c3.object_name,c3.overload)loop

          if(c4.data_level=0)then -- Compounded data type have data levels > 0 and all become SqlBinaries
            -- Map to .Net Framework SqlType in namespace System.Data.SqlTypes
            -- ** TODO: Correct the mappings - only some are correct **
            case c4.data_type
              when 'BFILE'                          then
                v_lang_data_type:='SqlInt64';
              when 'BINARY_DOUBLE'                  then
                v_lang_data_type:='SqlDouble';
              when 'BINARY_FLOAT'                   then
                v_lang_data_type:='SqlDouble';
              when 'BINARY_INTEGER'                 then
                v_lang_data_type:='SqlInt64';
              when 'BLOB'                           then
                v_lang_data_type:='SqlBinary';
              when 'CHAR'                           then
                v_lang_data_type:='SqlString';
              when 'CLOB'                           then
                v_lang_data_type:='SqlBinary';
              when 'DATE'                           then
                v_lang_data_type:='SqlDateTime';
              when 'FLOAT'                          then
                v_lang_data_type:='SqlDouble';
              when 'INTERVAL DAY TO SECOND'         then
                v_lang_data_type:='SqlInt64';
              when 'INTERVAL YEAR TO MONTH'         then
                v_lang_data_type:='SqlInt64';
              when 'LONG'                           then
                v_lang_data_type:='SqlString';
              when 'LONG RAW'                       then
                v_lang_data_type:='SqlBinary';
              when 'MLSLABEL'                       then
                v_lang_data_type:='SqlBinary';
              when 'NCHAR'                          then
                v_lang_data_type:='SqlString';
              when 'NCLOB'                          then
                v_lang_data_type:='SqlBinary';
              when 'NUMBER'                         then
                if(nvl(c4.data_length,22)=22)then
                  v_lang_data_type:='SqlInt64';
                else
                  v_lang_data_type:='SqlDecimal';
                end if;
              when 'NVARCHAR2'                      then
                v_lang_data_type:='SqlString';
              when 'OBJECT'                         then
                v_lang_data_type:='SqlBinary';
              when 'PL/SQL BOOLEAN'                 then
                v_lang_data_type:='SqlBoolean';
              when 'PL/SQL RECORD'                  then
                -- Should use a predefined oracle compounded data type instead here!
                -- Use data levels to construct the record items and make up a struct
                v_lang_data_type:='SqlBinary';
              when 'PL/SQL TABLE'                   then
                v_lang_data_type:='SqlBinary';
              when 'RAW'                            then
                v_lang_data_type:='SqlBinary';
              when 'REF'                            then
                v_lang_data_type:='OracleRefCursor';
              when 'REF CURSOR'                     then
                v_lang_data_type:='OracleRefCursor';
              when 'ROWID'                          then
                v_lang_data_type:='SqlGuid';
              when 'TABLE'                          then
                v_lang_data_type:='SqlBinary';
              when 'TIME'                           then
                v_lang_data_type:='SqlDateTime';
              when 'TIME WITH TIME ZONE'            then
                v_lang_data_type:='SqlDateTime';
              when 'TIMESTAMP'                      then
                v_lang_data_type:='SqlDateTime';
              when 'TIMESTAMP WITH LOCAL TIME ZONE' then
                v_lang_data_type:='SqlDateTime';
              when 'TIMESTAMP WITH TIME ZONE'       then
                v_lang_data_type:='SqlDateTime';
              when 'UNDEFINED'                      then
                if(c4.type_name='XMLTYPE')then
                  v_lang_data_type:='OracleXmlType';
                else
                  v_lang_data_type:='SqlBinary';
                end if;
              when 'UROWID'                         then
                v_lang_data_type:='SqlGuid';
              when 'VARCHAR2'                       then
                v_lang_data_type:='SqlString';
              when 'VARRAY'                         then
                v_lang_data_type:='SqlBinary';
              else
                v_lang_data_type:='SqlBinary';
            end case;
            v_lang_data_types(v_pos):=v_lang_data_type;
            v_pos:=v_pos+1;
            v_arg_name:=lower(nvl(c4.argument_name,v_ret_param_name));  -- No param name => returm parameter

            if(v_first=true)then
              v_sql:='        ';
            else
              v_sql:='       ,';
            end if;
            v_first:=false;

            case c4.in_out
              when 'IN' then
                v_sql:=v_sql||v_lang_data_type||' '||v_arg_name;
              when 'IN/OUT' then
                v_sql:=v_sql||'ref '||v_lang_data_type||' '||v_arg_name;
              when 'OUT' then
                v_sql:=v_sql||'ref '||v_lang_data_type||' '||v_arg_name;
              else
                v_sql:=v_sql||'ref '||v_lang_data_type||' '||v_arg_name;
            end case;
            utl_file.put_line(v_file_handle, v_sql);
          end if;
        end loop;

        utl_file.put_line(v_file_handle, '        )');
        utl_file.put_line(v_file_handle, '      {');
        utl_file.put_line(v_file_handle, '        // Set up command object;');
        utl_file.put_line(v_file_handle, '        cmd.CommandText="'||c1.owner||'.'||c2.object_name||'.'||c3.object_name||'";');
        utl_file.put_line(v_file_handle, '        cmd.CommandType=CommandType.StoredProcedure;');
        utl_file.put_line(v_file_handle, '        // Add parameters');

        -- Create Parameters prior to calling the store procedure
        for c4 in c_params(c3.owner,c3.package_name,c3.object_name,c3.overload)loop
          if(c4.data_level=0)then -- Compounded data type have data levels > 0 and all become SqlBinaries for now.
            case c4.data_type
              when 'BFILE'                          then
                v_mw_data_type:='OracleDbType.BFile';
              when 'BINARY_DOUBLE'                  then
                v_mw_data_type:='OracleDbType.Double';
              when 'BINARY_FLOAT'                   then
                v_mw_data_type:='OracleDbType.Decimal';
              when 'BINARY_INTEGER'                 then
                v_mw_data_type:='OracleDbType.Int32';
              when 'BLOB'                           then
                v_mw_data_type:='OracleDbType.Blob';
              when 'CHAR'                           then
                v_mw_data_type:='OracleDbType.Char';
              when 'CLOB'                           then
                v_mw_data_type:='OracleDbType.Clob';
              when 'DATE'                           then
                v_mw_data_type:='OracleDbType.Date';
              when 'FLOAT'                          then
                v_mw_data_type:='OracleDbType.Decimal';
              when 'INTERVAL DAY TO SECOND'         then
                v_mw_data_type:='OracleDbType.IntervalDS';
              when 'INTERVAL YEAR TO MONTH'         then
                v_mw_data_type:='OracleDbType.IntervalYM';
              when 'LONG'                           then
                v_mw_data_type:='OracleDbType.Long';
              when 'LONG RAW'                       then
                v_mw_data_type:='OracleDbType.LongRaw';
              when 'MLSLABEL'                       then
                v_mw_data_type:='OracleDbType.Varchar2';
              when 'NCHAR'                          then
                v_mw_data_type:='OracleDbType.NChar';
              when 'NCLOB'                          then
                v_mw_data_type:='OracleDbType.NClob';
              when 'NUMBER'                         then
                if(c4.data_length=22 and nvl(c4.data_precision,22)=22)then   -- TODO: questionable !
                  v_mw_data_type:='OracleDbType.Int32';
                else
                  v_mw_data_type:='OracleDbType.Decimal';
                end if;
              when 'NVARCHAR2'                      then
                v_mw_data_type:='OracleDbType.NVarchar2';
              when 'OBJECT'                         then
                v_mw_data_type:='OracleDbType.Long';
              when 'PL/SQL BOOLEAN'                 then
                v_mw_data_type:='OracleDbType.Int32';
              when 'PL/SQL RECORD'                  then
                v_mw_data_type:='OracleDbType.Long';
              when 'PL/SQL TABLE'                   then
                v_mw_data_type:='OracleDbType.Long';
              when 'RAW'                            then
                v_mw_data_type:='OracleDbType.Raw';
              when 'REF'                            then
                v_mw_data_type:='OracleDbType.RefCursor';
              when 'REF CURSOR'                     then
                v_mw_data_type:='OracleDbType.RefCursor';
              when 'ROWID'                          then
                v_mw_data_type:='OracleDbType.Int64';
              when 'TABLE'                          then
                v_mw_data_type:='OracleDbType.Long';
              when 'TIME'                           then
                v_mw_data_type:='OracleDbType.TimeStamp';
              when 'TIME WITH TIME ZONE'            then
                v_mw_data_type:='OracleDbType.TimeStampTZ';
              when 'TIMESTAMP'                      then
                v_mw_data_type:='OracleDbType.TimeStamp';
              when 'TIMESTAMP WITH LOCAL TIME ZONE' then
                v_mw_data_type:='OracleDbType.TimeStampLTZ';
              when 'TIMESTAMP WITH TIME ZONE'       then
                v_mw_data_type:='OracleDbType.TimeStampTZ';
              when 'UNDEFINED'                      then
                if(c4.type_name='XMLTYPE')then
                  v_mw_data_type:='OracleDbType.XmlType';
                else
                  v_mw_data_type:='OracleDbType.Raw';
                end if;
              when 'UROWID'                         then
                v_mw_data_type:='OracleDbType.Int64';
              when 'VARCHAR2'                       then
                v_mw_data_type:='OracleDbType.Varchar2';
              when 'VARRAY'                         then
                v_mw_data_type:='OracleDbType.Long';
              else
                v_mw_data_type:='OracleDbType.Int32';
            end case;

            v_arg_name:=lower(nvl(c4.argument_name,v_ret_param_name));
            case c4.in_out
              when 'OUT' then
                if(c4.position=0)then
                  -- Create a return parameter
                  utl_file.put_line(v_file_handle,   '        cmd.Parameters.Add("'||v_arg_name||'",'||v_mw_data_type||',DBNull.Value,ParameterDirection.ReturnValue);');
                else
                  -- Create an output parameter
                  if(v_mw_data_type='OracleDbType.Varchar2')then
                    utl_file.put_line(v_file_handle, '        cmd.Parameters.Add("'||v_arg_name||'",'||v_mw_data_type||','||v_out_string_size||',DBNull.Value,ParameterDirection.Output);');
                  else
                    utl_file.put_line(v_file_handle, '        cmd.Parameters.Add("'||v_arg_name||'",'||v_mw_data_type||',DBNull.Value, ParameterDirection.Output);');
                  end if;
                end if;
              when 'IN' then
                -- Create a input parameter
                if(c4.data_type='UNDEFINED')then
                  utl_file.put_line(v_file_handle,     '        if('||v_arg_name||'.IsEmpty){');
                else
                  utl_file.put_line(v_file_handle,     '        if('||v_arg_name||'.IsNull){');
                end if;
                utl_file.put_line(v_file_handle,     '          cmd.Parameters.Add("'||v_arg_name||'",'||v_mw_data_type||',DBNull.Value,ParameterDirection.Input);');
                utl_file.put_line(v_file_handle,     '        }else{');
                utl_file.put_line(v_file_handle,     '          cmd.Parameters.Add("'||v_arg_name||'",'||v_mw_data_type||','||v_arg_name||'.Value, ParameterDirection.Input);');
                utl_file.put_line(v_file_handle,     '        }');
              when 'IN/OUT' then
                -- Create a input/output parameter
                if(v_mw_data_type='OracleDbType.RefCursor')then
                  utl_file.put_line(v_file_handle, '        cmd.Parameters.Add("'||v_arg_name||'",'||v_mw_data_type||',DBNull.Value, ParameterDirection.InputOutput);');
                else
                  if(c4.data_type='UNDEFINED')then
                    utl_file.put_line(v_file_handle,     '        if('||v_arg_name||'.IsEmpty){');
                  else
                    utl_file.put_line(v_file_handle,     '        if('||v_arg_name||'.IsNull){');
                  end if;
                  if(v_mw_data_type='OracleDbType.Varchar2')then
                    utl_file.put_line(v_file_handle,   '          cmd.Parameters.Add("'||v_arg_name||'",'||v_mw_data_type||','||v_out_string_size||',DBNull.Value,ParameterDirection.InputOutput);');
                  else
                    utl_file.put_line(v_file_handle,   '          cmd.Parameters.Add("'||v_arg_name||'",'||v_mw_data_type||',DBNull.Value,ParameterDirection.InputOutput);');
                  end if;
                  utl_file.put_line(v_file_handle,     '        }else{');
                  utl_file.put_line(v_file_handle,     '          cmd.Parameters.Add("'||v_arg_name||'",'||v_mw_data_type||','||v_arg_name||'.Value,ParameterDirection.InputOutput);');
                  utl_file.put_line(v_file_handle,     '        }');
                end if;
              else
                utl_file.put_line(v_file_handle,     '        // Unknown parameter type '||v_arg_name);
            end case;
          end if;
        end loop;

        -- Execute the stored procedure
        utl_file.put_line(v_file_handle, '        // Execute stored procedure:');
        utl_file.put_line(v_file_handle, '        cmd.ExecuteNonQuery();');

        -- Load the values of resulting OUT and IN/OUT parameters into
        --  the earlier-created wrapper-function parameters
        v_pos:=0;
        v_arg_count:=0;
        v_out_arg_count:=0;
        for c4 in c_params(c3.owner,c3.package_name,c3.object_name,c3.overload)loop
          v_arg_count:=v_arg_count+1;
          if(c4.data_level=0)then
            -- Compounded data types have data levels > 0 and all become SqlBinaries for now.
            -- TODO: Deal with compunded data types, as these are wonderful things!

            if(c4.in_out='IN/OUT' or c4.in_out='OUT')then
              -- TEMP {{
              --v_lang_data_type:=v_lang_data_types(v_pos);
              case c4.data_type
                when 'BFILE'                          then
                  v_lang_data_type:='SqlInt64';
                when 'BINARY_DOUBLE'                  then
                  v_lang_data_type:='SqlDouble';
                when 'BINARY_FLOAT'                   then
                  v_lang_data_type:='SqlDouble';
                when 'BINARY_INTEGER'                 then
                  v_lang_data_type:='SqlInt64';
                when 'BLOB'                           then
                  v_lang_data_type:='SqlBinary';
                when 'CHAR'                           then
                  v_lang_data_type:='SqlString';
                when 'CLOB'                           then
                  v_lang_data_type:='SqlBinary';
                when 'DATE'                           then
                  v_lang_data_type:='SqlDateTime';
                when 'FLOAT'                          then
                  v_lang_data_type:='SqlDouble';
                when 'INTERVAL DAY TO SECOND'         then
                  v_lang_data_type:='SqlInt64';
                when 'INTERVAL YEAR TO MONTH'         then
                  v_lang_data_type:='SqlInt64';
                when 'LONG'                           then
                  v_lang_data_type:='SqlString';
                when 'LONG RAW'                       then
                  v_lang_data_type:='SqlBinary';
                when 'MLSLABEL'                       then
                  v_lang_data_type:='SqlBinary';
                when 'NCHAR'                          then
                  v_lang_data_type:='SqlString';
                when 'NCLOB'                          then
                  v_lang_data_type:='SqlBinary';
                when 'NUMBER'                         then
                  if(nvl(c4.data_length,22)=22)then
                    v_lang_data_type:='SqlInt64';
                  else
                    v_lang_data_type:='SqlDecimal';
                  end if;
                when 'NVARCHAR2'                      then
                  v_lang_data_type:='SqlString';
                when 'OBJECT'                         then
                  v_lang_data_type:='SqlBinary';
                when 'PL/SQL BOOLEAN'                 then
                  v_lang_data_type:='SqlBoolean';
                when 'PL/SQL RECORD'                  then
                  -- Should use a predefined oracle compounded data type instead here!
                  -- Use data levels to construct the record items and make up a struct
                  v_lang_data_type:='SqlBinary';
                when 'PL/SQL TABLE'                   then
                  v_lang_data_type:='SqlBinary';
                when 'RAW'                            then
                  v_lang_data_type:='SqlBinary';
                when 'REF'                            then
                  v_lang_data_type:='OracleRefCursor';
                when 'REF CURSOR'                     then
                  v_lang_data_type:='OracleRefCursor';
                when 'ROWID'                          then
                  v_lang_data_type:='SqlGuid';
                when 'TABLE'                          then
                  v_lang_data_type:='SqlBinary';
                when 'TIME'                           then
                  v_lang_data_type:='SqlDateTime';
                when 'TIME WITH TIME ZONE'            then
                  v_lang_data_type:='SqlDateTime';
                when 'TIMESTAMP'                      then
                  v_lang_data_type:='SqlDateTime';
                when 'TIMESTAMP WITH LOCAL TIME ZONE' then
                  v_lang_data_type:='SqlDateTime';
                when 'TIMESTAMP WITH TIME ZONE'       then
                  v_lang_data_type:='SqlDateTime';
                when 'UNDEFINED'                      then
                  if(c4.type_name='XMLTYPE')then
                    v_lang_data_type:='OracleXmlType';
                  else
                    v_lang_data_type:='SqlBinary';
                  end if;
                when 'UROWID'                         then
                  v_lang_data_type:='SqlGuid';
                when 'VARCHAR2'                       then
                  v_lang_data_type:='SqlString';
                when 'VARRAY'                         then
                  v_lang_data_type:='SqlBinary';
                else
                  v_lang_data_type:='SqlBinary';
              end case;
              -- }}

              v_arg_name:=lower(c4.argument_name);
              -- RETURN PARAMETER:
              if(v_arg_name is null)then
                -- No arg name means that it is a return parameter
                utl_file.put_line(v_file_handle,    '        // Set Stored procedure''s RETURN argument:');
                v_arg_name:=lower(v_ret_param_name);
                case v_lang_data_type
                  when 'SqlInt64' then
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = new '||v_lang_data_type||'((int)cmd.Parameters["'||v_arg_name||'"].Value);');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlInt32' then
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = new '||v_lang_data_type||'((int)cmd.Parameters["'||v_arg_name||'"].Value);');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlInt16' then
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = new '||v_lang_data_type||'((int)cmd.Parameters["'||v_arg_name||'"].Value);');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlSingle' then
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = new '||v_lang_data_type||'((double)cmd.Parameters["'||v_arg_name||'"].Value);');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlMoney' then
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = new '||v_lang_data_type||'((double)cmd.Parameters["'||v_arg_name||'"].Value);');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlDouble' then
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = new '||v_lang_data_type||'((double)cmd.Parameters["'||v_arg_name||'"].Value);');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlDecimal' then
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = new '||v_lang_data_type||'((double)cmd.Parameters["'||v_arg_name||'"].Value);');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlBinary' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = new '||v_lang_data_type||'((byte[])cmd.Parameters["'||v_arg_name||'"].Value);');
                  when 'SqlBoolean' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = new '||v_lang_data_type||'((int)cmd.Parameters["'||v_arg_name||'"].Value);');
                  when 'SqlByte' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = new '||v_lang_data_type||'((byte)cmd.Parameters["'||v_arg_name||'"].Value);');
                  when 'SqlString' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = new '||v_lang_data_type||'((string)cmd.Parameters["'||v_arg_name||'"].Value);');
                  when 'SqlGuid' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = new '||v_lang_data_type||'((string)cmd.Parameters["'||v_arg_name||'"].Value);');
                  when 'SqlDateTime' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = new '||v_lang_data_type||'((DateTime)cmd.Parameters["'||v_arg_name||'"].Value);');
                  when 'OracleXmlType' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = new '||v_lang_data_type||'(cmd.Parameters["'||v_arg_name||'"].GetOracleXmlType;');
                  else
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = ('||v_lang_data_type||')cmd.Parameters["'||v_arg_name||'"].Value;');
                end case;
              else
                -- OUT and IN/OUT:
                -- This is an OUT or IN/OUT parameter that is passed back by reference
                v_out_arg_count:=v_out_arg_count+1;
                if(v_out_arg_count=1)then
                  utl_file.put_line(v_file_handle, '        // Set Stored procedure''s OUT argument(s):');
                end if;

                case v_lang_data_type
                  when 'SqlInt64' then
                    -- Check that the OUT'ed value is not null
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = (int)cmd.Parameters["'||v_arg_name||'"].Value;'); -- Need to cast to int and not long!
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlInt32' then
                    -- Check that the OUT'ed value is not null
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = (int)cmd.Parameters["'||v_arg_name||'"].Value;');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlInt16' then
                    -- Check that the OUT'ed value is not null
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = (int)cmd.Parameters["'||v_arg_name||'"].Value;');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlSingle' then
                    -- Check that the OUT'ed value is not null
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = (double)cmd.Parameters["'||v_arg_name||'"].Value;');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlMoney' then
                    -- Check that the OUT'ed value is not null
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = (double)cmd.Parameters["'||v_arg_name||'"].Value;');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlDouble' then
                    -- Check that the OUT'ed value is not null
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = (double)cmd.Parameters["'||v_arg_name||'"].Value;');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlDecimal' then
                    -- Check that the OUT'ed value is not null
                    utl_file.put_line(v_file_handle,'        if(!cmd.Parameters["'||v_arg_name||'"].Status.Equals(OracleParameterStatus.NullFetched)){');
                    utl_file.put_line(v_file_handle,'          '||v_arg_name||' = (double)cmd.Parameters["'||v_arg_name||'"].Value;');
                    utl_file.put_line(v_file_handle,'        }');
                  when 'SqlBinary' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = (byte[])cmd.Parameters["'||v_arg_name||'"].Value;');
                  when 'SqlBoolean' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = (int)cmd.Parameters["'||v_arg_name||'"].Value;');
                  when 'SqlByte' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = (byte)cmd.Parameters["'||v_arg_name||'"].Value;');
                  when 'SqlString' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = cmd.Parameters["'||v_arg_name||'"].Value.ToString();');
                  when 'SqlGuid' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = cmd.Parameters["'||v_arg_name||'"].Value.ToString();');
                  when 'SqlDateTime' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = (DateTime)cmd.Parameters["'||v_arg_name||'"].Value;');
                  when 'OracleRefCursor' then
                    utl_file.put_line(v_file_handle,'        '||v_arg_name||' = ('||v_lang_data_type||')cmd.Parameters["'||v_arg_name||'"].Value;');
                end case;
              end if;
            end if;
          end if;
          v_pos:=v_pos+1;
        end loop;
        utl_file.put_line(v_file_handle,        '        return 0;');
        utl_file.put_line(v_file_handle,        '      } //...method '||v_proc_name);
        utl_file.put_line(v_file_handle,        ' ');
      end loop;
      utl_file.put_line(v_file_handle,          '    } //...class '||v_class_name);
      utl_file.put_line(v_file_handle,          '    #endregion');
      utl_file.put_line(v_file_handle,          ' ');
    end loop;
    utl_file.put_line(v_file_handle,            '  } //...namespace '||v_namespace_name);
    utl_file.put_line(v_file_handle,            '} //...namespace OracleWrapper');

    -- File closing
    utl_file.put_line(v_file_handle, '//----------------------------------------------------------------------------');
    utl_file.put_line(v_file_handle, '// end of file');
    utl_file.put_line(v_file_handle, '//----------------------------------------------------------------------------');
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

