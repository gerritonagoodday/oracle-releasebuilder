------------------------------------------------------------------------
------------------------------------------------------------------------
--  DESCRIPTION:
--  Compile all application objects on a database.
--
--  USAGE:
--  sqlplus / as sysdba @compile.sql
------------------------------------------------------------------------
whenever SQLERROR exit failure
whenever OSERROR exit failure
set serveroutput on size 1000000;
set pagesize 0
set verify off
set feedback off
set echo off
set pages 100
set linesize 120

prompt Compiling all database objects
-- Recompiles all packages/procedures/functions and views in the schema list
-- until it there is no change in the over all compilation status.
-- Based on code by Solomon Yakobson:
--    Objects are recompiled based on object dependencies and
--    therefore compiling  all requested objects in one path.
--    Recompile Utility skips every object which is either of
--    unsupported object type or depends on INVALID object(s)
--    outside of current request (which means we know upfront
--    compilation will fail anyway).  if object recompilation
--    is not successful, Recompile Utility continues with the
--    next object.
--
declare
  o_name    constant varchar2(10):='%';
  o_type    constant varchar2(10):='%';
  c_invalid constant varchar2(12):='INVALID';
  c_valid   constant varchar2(12):='VALID';

  -- Get all users that match this string criteria
  cursor c_users is
    select username
      from sys.dba_users
     order by 1;


  -- Exceptions
  success_with_error EXCEPTION;
  pragma exception_init (success_with_error, -24344);

  -- Return Codes
  invalid_type constant integer:=1;
  invalid_parent constant integer:=2;
  compile_errors constant integer:=4;
  cnt number;
  dyncur integer;
  type_status integer:=0;
  parent_status integer:=0;
  recompile_status integer:=0;
  object_status varchar2 (30);

  cursor invalid_parent_cursor (
      oowner varchar2
    , oname varchar2
    , otype varchar2
    , ostatus varchar2
    , oid number
   )
   IS
      select /*+ rule */
             o.object_id
        from public_dependency d, all_objects o
       where d.object_id = oid
         and o.object_id = d.referenced_object_id
         AND o.status != c_valid
      minus
      select /*+ rule */
             object_id
        from all_objects
       where owner like upper (oowner)
         and object_name like upper (oname)
         and object_type like upper (otype)
         and status like upper (ostatus);

  cursor recompile_cursor (oid number)is
     select /*+ rule */
             'ALTER '
         || DECODE (object_type
                  , 'PACKAGE BODY', 'PACKAGE'
                  , 'TYPE BODY', 'TYPE'
                  , object_type
                   )
         || ' '
         || owner
         || '.'
         || object_name
         || ' COMPILE '
         || DECODE (object_type
                  , 'PACKAGE BODY', ' BODY'
                  , 'TYPE BODY', 'BODY'
                  , 'TYPE', 'SPECifICATION'
                  , ''
                   ) stmt
           , object_type, owner, object_name
      from all_objects
     where object_id = oid;

  recompile_record recompile_cursor%ROWTYPE;
  cursor obj_cursor (
      oowner VARCHAR2
    , oname VARCHAR2
    , otype VARCHAR2
    , ostatus VARCHAR2
  ) is
     select /*+ RULE */
            max(level) dlevel, object_id
       from sys.public_dependency
      start with object_id in (
                    select object_id
                      from all_objects
                     where owner like upper (oowner)
                       and object_name like upper (oname)
                       and object_type like upper (otype)
                       and status like upper (ostatus))
    connect by object_id = prior referenced_object_id
      group by object_id
     having min(level) = 1
      union all
     select 1 dlevel, object_id
       from all_objects o
      where owner like upper (oowner)
        and object_name like upper (oname)
        and object_type like upper (otype)
        and status like upper (ostatus)
        and not exists (select 1
                          from sys.public_dependency d
                         where d.object_id = o.object_id)
      order by 1 desc;

   cursor status_cursor(oid number)
   is
      select /*+ rule */
             status
        from all_objects
       where object_id = oid;

begin
  for c_user in c_users loop
    -- Recompile requested objects based on their dependency levels.
    dyncur:=DBMS_SQL.open_cursor;
    for obj_record in obj_cursor(c_user.username, o_name, o_type, c_invalid) loop
      open  recompile_cursor(obj_record.object_id);
      fetch recompile_cursor
       into recompile_record;
      close recompile_cursor;

      -- We can recompile only Functions, Packages, Package Bodies,
      -- Procedures, Triggers, Views, Types and Type Bodies.
      if recompile_record.object_type IN
            ('FUNCTION','PACKAGE','PACKAGE BODY','PROCEDURE','TRIGGER','VIEW','TYPE','TYPE BODY')
      then
        -- There is no sense to recompile an object that depends on
        -- invalid objects outside of the current recompile request.
        open invalid_parent_cursor(c_user.username,o_name,o_type,c_invalid,obj_record.object_id);
        fetch invalid_parent_cursor into cnt;
        if(invalid_parent_cursor%notfound)then
          -- Recompile object.
          begin
            dbms_sql.parse(dyncur,recompile_record.stmt,dbms_sql.native);
          exception
            when success_with_error then
              null;
          end;

          open status_cursor (obj_record.object_id);
          fetch status_cursor
          into object_status;
          close status_cursor;
          if(object_status <> c_valid)then
            recompile_status:=compile_errors;
          end if;
        else
        parent_status:=invalid_parent;
      end if;
        close invalid_parent_cursor;
      else
        type_status:=invalid_type;
      end if;
    end loop;
    dbms_sql.close_cursor (dyncur);
  end loop;
exception
  when others then
    dbms_output.put_line('* Exception ['||sqlcode||']. Message ['||sqlerrm||']');
    if obj_cursor%isopen then
       close obj_cursor;
    end if;
    if recompile_cursor%isopen then
       close recompile_cursor;
    end if;
    if invalid_parent_cursor%isopen then
       close invalid_parent_cursor;
    end if;
    if status_cursor%isopen then
       close status_cursor;
    end if;
    if dbms_sql.is_open (dyncur) then
       dbms_sql.close_cursor (dyncur);
    end if;
    raise;
end;
/

-- Report on console uncompiled objects
-- This will return nothing if no invalid objects exist
column  invalid_object format a40 Heading 'Invalid Database Object Summary'
column  item           format a5  Heading 'Item'
compute number label 'Total' of invalid_object on item
break on report
select lpad(trim(rownum),5) as item,
       rpad(object_type,12)||': '||owner||'.'||object_name as invalid_object
  from sys.dba_objects
 where trim(object_type) in ('PACKAGE','PACKAGE BODY','PROCEDURE','FUNCTION','TRIGGER','VIEW','TYPE','TYPE BODY')
   and status = 'INVALID'
 order by item, object_type,owner,object_name;

exit;

------------------------------------------------------------------------
-- end of file
------------------------------------------------------------------------

