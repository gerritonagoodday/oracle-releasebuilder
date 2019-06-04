#!/bin/bash
#-----------------------------------------------------------------------------
#--  $Header$
#-----------------------------------------------------------------------------
# Build script for external Oracle procedures 
#
# This script should be run from the UNIX shell under the Oracle Admin User.
#-----------------------------------------------------------------------------

#=============================================================================
# Map Oracle PLSQL types to External types  
# Note that multi-word strings have spaces substituted by spaces
function OraParm2ExtParmType {
  case shift in
    BINARY_INTEGER          )
      EXT_PARM_TYPE="STRING ";;
    BOOLEAN                 )
      EXT_PARM_TYPE="STRING ";;
    PLS_INTEGER             )
      EXT_PARM_TYPE="STRING ";;
    NATURAL                 )
      EXT_PARM_TYPE="UNSIGNED INT ";;
    NATURALN                )
      EXT_PARM_TYPE="UNSIGNED INT ";;
    POSITIVE                )
      EXT_PARM_TYPE="UNSIGNED INT ";;
    POSITIVEN               )
      EXT_PARM_TYPE="UNSIGNED INT ";;
    SIGNTYPE                )
      EXT_PARM_TYPE="UNSIGNED INT ";;
    FLOAT                   )
      EXT_PARM_TYPE="FLOAT ";;
    REAL                    )
      EXT_PARM_TYPE="FLOAT ";;
    DOUBLE                  )
      EXT_PARM_TYPE="DOUBLE ";;
    PRECISION               )
      EXT_PARM_TYPE="DOUBLE ";;
    CHAR                    )
      EXT_PARM_TYPE="STRING ";;
    CHARACTER               )
      EXT_PARM_TYPE="STRING ";;
    LONG                    )
      EXT_PARM_TYPE="STRING ";;
    NCHAR                   )
      EXT_PARM_TYPE="STRING ";;
    NVARCHAR2               )
      EXT_PARM_TYPE="STRING ";;
    ROWID                   )
      EXT_PARM_TYPE="STRING ";;
    VARCHAR                 )
      EXT_PARM_TYPE="STRING ";;
    VARCHAR2                )
      EXT_PARM_TYPE="STRING ";;
    LONG_RAW                )
      EXT_PARM_TYPE="RAW ";;
    RAW                     )
      EXT_PARM_TYPE="RAW ";;
    BFILE                   )
      EXT_PARM_TYPE="OCILOBLOCATOR ";;
    BLOB                    )
      EXT_PARM_TYPE="OCILOBLOCATOR ";;
    CLOB                    )
      EXT_PARM_TYPE="OCILOBLOCATOR ";;
    NCLOB                   )
      EXT_PARM_TYPE="OCILOBLOCATOR ";;
    NUMBER                  )
      EXT_PARM_TYPE="OCINUMBER ";;
    DATE                    )
      EXT_PARM_TYPE="OCIDATE ";;  
    TIMESTAMP               )
      EXT_PARM_TYPE="OCIDateTime ";;  
    TIMESTAMP_WITH_TIME     )
      EXT_PARM_TYPE="OCIDateTime ";;  
    ZONE                    )
      EXT_PARM_TYPE="OCIDateTime ";;  
    TIMESTAMP_WITH_LOCAL    ) 
      EXT_PARM_TYPE="OCIDateTime ";;  
    TIME_ZONE               )
      EXT_PARM_TYPE="OCIDateTime ";;  
    INTERVAL_DAY_TO_SECOND  )
      EXT_PARM_TYPE="OCIInterval ";;  
    INTERVAL_YEAR_TO_MONTH  )
      EXT_PARM_TYPE="OCIInterval ";;  
  esac  
  export EXT_PARM_TYPE
}


# Main starts here

# Name of External Procedure
EXTPROC_NAME="hostcmd"
# Language
EXTPROC_LANG="C"
# Source files
EXTPROC_SRC="hostcmd.c"
# Object files
for item in ${EXTPROC_SRC}; do
  EXTPROC_OBJ="${EXTPROC_OBJ}${item%%.*}.o "
done


# Parameters: You need to have manually mapped the parameters of the C
# or Java proc to Oracle types already to proceed. Confused? Go to 
# http://download-west.oracle.com/docs/cd/B10501_01/appdev.920/a96590/adg11rtn.htm#1001153
# May automate this one day but it will change this interface. 
#
# Parameter Names
EXTPROC_PARAM_NAMES="p_cmd"
# Paramters Directions
EXTPROC_PARAM_DIRECTIONS="in"
# Oracle Parameter Types
EXTPROC_PARAM_TYPES="varchar2"
# Oracle return type
EXTPROC_RETURN_TYPE="binary_integer"


# Location of resulting binary file
EXTPROC_BIN_DIR="${ORACLE_BASE}/admin/${ORACLE_SID}/bin"
# Oracle schema 
EXTPROC_SCHEMA="UTL"
# Oracle Library name
EXTPROC_LIB="${EXTPROC_NAME}_lib"

echo "Building external ${EXTPROC_LANG}-procedure ${EXTPROC_NAME}..."

if [[ $EXTPROC_LANG -ne "C" ]]; then
  echo "This build script is only able to do C-based external procedures."
  echo "Exiting..."
  exit 1
fi

echo "Building binary to host external procedure"
echo "Compiling"
gcc -c ${EXTPROC_SRC}
ERRNO=$?
if [[ $ERRNO -ne 0 ]]; then
  echo "Failed to compile external procedure. Error ${ERRNO}."
  echo "Exiting..."
  exit 1 
fi

echo "Linking"
# Try linking against the system-independant make files
# Does not work in HP-UX, so we also try the manual approach with O/S specific flags for ld
if [[ $(uname) -ne "HP-UX" ]]; then
  make -f $ORACLE_HOME/rdbms/demo/demo_rdbms.mk extproc_callback SHARED_LIBNAME=${EXTPROC_NAME}.so OBJS=${EXTPROC_OBJ}
  ERRNO=$?
else
  ld -r -o ${EXTPROC_NAME}.so ${EXTPROC_OBJ}
fi
ERRNO=$?
if [[ $ERRNO -ne 0 ]]; then
  echo "Failed to link external procedure. Error ${ERRNO}."
  echo "Exiting..."
  exit 1 
fi

echo "Setting binary to executable"
chmod 775 ${EXTPROC_NAME}.so
ERRNO=$?
if [[ $ERRNO -ne 0 ]]; then
  echo "Failed to build external procedure. Error ${ERRNO}."
  echo "Exiting..."
  exit 1 
fi

echo "Determining target directory"
if [[ ! -d $EXTPROC_BIN_DIR ]]; then
  echo "Target directory $EXTPROC_BIN_DIR"
  echo "  does not exist. Creating it..."
  mkdir -p $EXTPROC_BIN_DIR 
  ERRNO=$?
  if [[ $ERRNO -ne 0 ]];   then
    echo "Failed to create target directory"
    echo "  $EXTPROC_BIN_DIR. Error ${ERRNO}."
    echo "Exiting..."
    exit 1
  fi
fi

echo "Copying to taget directory"
cp ${EXTPROC_NAME}.so $EXTPROC_BIN_DIR/.
ERRNO=$?
if [[ ERRNO -ne 0 ]]; then
  echo "Could not copy external procedure to"
  echo "  $EXTPROC_BIN_DIR."
  echo "Exiting..."
  exit 1
fi

echo "Dropping previously-existing External Process alias library"
sqlplus "/ as sysdba" > /dev/null <<!
whenever oserror exit failure;
whenever sqlerror exit failure;
set serveroutput on size 1000000;
declare
  v_count         number;
begin
  select count(*)
    into v_count
    from sys.all_libraries
   where upper(owner) = upper('${EXTPROC_SCHEMA}')
     and library_name = '${EXTPROC_LIB}';
  if(v_count>0)then
    dbms_output.put_line('Library ${EXTPROC_SCHEMA}.${EXTPROC_LIB} already exists. Dropping it.');
    execute immediate 'drop library ${EXTPROC_SCHEMA}.${EXTPROC_LIB}';
    dbms_output.put_line('Successfully dropped library ${EXTPROC_SCHEMA}.${EXTPROC_LIB}.');
  end if;
exception
  when others then
    dbms_output.put_line(sqlerrm||' while attempting to drop previoustly-existing external functions and libraries.');
end;
/
!
if [[ $? -ne 0 ]]
then
  echo "Exiting..."
  exit 1
fi

echo "Registering External Process library"
sqlplus "/ as sysdba" > /dev/null <<!
set serveroutput on size 1000000;
whenever oserror exit failure;
whenever sqlerror exit failure;
begin
  execute immediate 'create library ${EXTPROC_SCHEMA}.${EXTPROC_LIB} as ''${EXTPROC_BIN_DIR}/${EXTPROC_NAME}.so''';
  dbms_output.put_line('Successfully created library ${EXTPROC_SCHEMA}.${EXTPROC_LIB}.');
exception
  when others then
    dbms_output.put_line(sqlerrm||' while attempting to register library ${EXTPROC_SCHEMA}.${EXTPROC_LIB}.');
end;
/
!
if [[ $? -ne 0 ]]; then
  echo "Exiting..."
  exit 1
else
  echo "Success."
fi

echo "Creating ${EXTPROC_NAME} function"
# This makes up a sql creation script such as 
# SQL>  create or replace function utl.hostcmd(p_cmd in varchar2) return binary_integer
#       as external name "hostcmd"
#       library utl.hostcmd_lib
#       language C
#       parameters (p_cmd STRING, RETURN INT);
[[ ! -z $EXTPROC_RETURN_TYPE ]] SQL="create or replace function " || SQL="create or replace procedure " 
SQL="${SQL}${EXTPROC_SCHEMA}.${EXTPROC_NAME} "
if [[ ! -z $EXTPROC_PARAM_NAMES ]]; then
  SQL="${SQL}("
  index=0  
  $EXTPROC_PARAM_NAMES_=${EXTPROC_PARAM_NAMES}
  $EXTPROC_PARAM_DIRECTIONS_=${EXTPROC_PARAM_DIRECTIONS}
  $EXTPROC_PARAM_TYPES_=${EXTPROC_PARAM_TYPES}
  
  $EXTPROC_PARAM_NAMES__=${EXTPROC_PARAM_NAMES_%%:*}
  $EXTPROC_PARAM_DIRECTIONS__=${EXTPROC_PARAM_DIRECTIONS_%%:*}
  $EXTPROC_PARAM_TYPES__=${EXTPROC_PARAM_TYPES_%%:*}
  
  while [[ -n $EXTPROC_PARAM_NAMES__ ]]; do
    index=$((index+1))
    [[ $index -gt 1 ]] && SQL="${SQL}, "
    SQL="${SQL}$EXTPROC_PARAM_NAMES__ $EXTPROC_PARAM_DIRECTIONS__ $EXTPROC_PARAM_TYPES__"

    $EXTPROC_PARAM_NAMES_=${EXTPROC_PARAM_NAMES_#*:}
    $EXTPROC_PARAM_DIRECTIONS_=${EXTPROC_PARAM_DIRECTIONS_#*:}
    $EXTPROC_PARAM_TYPES_=${EXTPROC_PARAM_TYPES_#*:}

    $EXTPROC_PARAM_NAMES__=${EXTPROC_PARAM_NAMES_%%:*}
    $EXTPROC_PARAM_DIRECTIONS__=${EXTPROC_PARAM_DIRECTIONS_%%:*}
    $EXTPROC_PARAM_TYPES__=${EXTPROC_PARAM_TYPES_%%:*}    
  done
  SQL="${SQL}) "
fi
[[ ! -z $EXTPROC_RETURN_TYPE ]] SQL="return $EXTPROC_RETURN_TYPE "
SQL="${SQL}as external name \"${EXTPROC_NAME}\" "
SQL="${SQL}library ${EXTPROC_SCHEMA}.${EXTPROC_LIB} "
SQL="${SQL}language ${EXTPROC_LANG} "
if [[ ! -z $EXTPROC_PARAM_NAMES ]]; then
  SQL="${SQL}parameters ("
  # Make our live easier by changing multi-word types to single word types
  EXTPROC_PARAM_TYPES_=$(echo $EXTPROC_PARAM_TYPES | \
    sed -e s/LONG RAW/LONG_RAW/ig \
        -e s/TIMESTAMP WITH TIME/TIMESTAMP_WITH_TIME/ig \
        -e s/TIMESTAMP WITH LOCAL/TIMESTAMP_WITH_LOCAL/ig \
        -e s/TIME ZONE/TIME_ZONE/ig \
        -e s/INTERVAL DAY TO SECOND/INTERVAL_DAY_TO_SECOND/ig \
        -e s/INTERVAL YEAR TO MONTH/INTERVAL_YEAR_TO_MONTH/ig)
  # Map Oracle PLSQL types to External types  
  index=0
  for item in ${EXTPROC_PARAM_NAMES}; do
    index=$((index+1))
    [[ $index -gt 1 ]] && SQL="${SQL}, "
    OraParm2ExtParmType $i
    SQL=${SQL}${EXTPROC_PARAM_NAMES[$i]} ${EXT_PARM_TYPE}    
  done  
fi
if [[ ! -z $EXTPROC_RETURN_TYPE ]]; then
  [[ ! -z $EXTPROC_PARAM_NAMES ]] && SQL="${SQL}, " 
  OraParm2ExtParmType $EXTPROC_RETURN_TYPE
  SQL=${SQL} RETURN ${EXT_PARM_TYPE}
fi
SQL="$SQL )"

sqlplus "/ as sysdba" > /dev/null <<!
set serveroutput on size 1000000;
whenever oserror exit failure;
whenever sqlerror exit failure;
$SQL
as external name "${EXTPROC_NAME}"
library ${EXTPROC_SCHEMA}.${EXTPROC_LIB}
language C
parameters (p_cmd STRING, RETURN INT);
/
!
if [[ $? -ne 0 ]]; then
  echo "Exiting..."
  exit 1
else
  echo "Success."
fi

echo "Granting execute rights to function"
sqlplus "/ as sysdba" > /dev/null <<!
grant execute on ${EXTPROC_SCHEMA}.${EXTPROC_NAME} to public;
!

echo "Creating public synonym to function"
sqlplus "/ as sysdba" > /dev/null <<!
set serveroutput on size 1000000;
whenever oserror exit failure;
whenever sqlerror exit failure;
declare
  v_retcode   pls_integer;
  v_count     pls_integer;
begin
  dbms_output.put_line('Creating public synonyms:');
  -- #Drop synonym first if it already exists
  -- #Oracle 8i does not like CREATE OR REPLACE
  select count(*)
    into v_count
    from sys.all_synonyms
  where owner = 'PUBLIC'
    and upper(synonym_name) = upper('${EXTPROC_NAME}');
  if(v_count>0)then
    execute immediate 'drop public synonym ${EXTPROC_NAME}';
    dbms_output.put_line('Successfully dropped public synonym ${EXTPROC_NAME}.');
  end if;
  execute immediate 'create public synonym hostcmd for ${EXTPROC_SCHEMA}.${EXTPROC_NAME}';
  dbms_output.put_line('Successfully created public synonym ${EXTPROC_NAME}.');
exception
  when others then
    dbms_output.put_line(sqlerrm||' while creating public synonyms.');
end;
/
!
if [[ $? -ne 0 ]]
then
  echo "Exiting..."
  exit 1
else
  echo "Success."
fi

