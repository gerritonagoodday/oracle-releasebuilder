#!/bin/bash
###############################################################################
###############################################################################
#  DESCRIPTION:
#  This script generates the analyses script that will analyse all the tables
#  in the following schemas on the %ORACLE_SID% instance:
#  %APPLICATION_SCHEMAS%
#
#  PREPARATION:
#  1. This script can be run from any directory.
#  2. This script should be executable. If unsure, type:
#     chmod +x %ORACLE_SID%_analyse
#  3. This script should be run as the Oracle Admin. user. This user is usually
#     configured as oracle:oinstall.
#
#  USAGE:
#  Ideally, this script should be run in a regular basis.
#  This can be implemented by adding it to a Oracle Admin's crontab:
#  As user oracle:
#  $ crontab -e
#  i (for insert mode)
#  10 0 * * * %ORACLE_BASE%/bin/%ORACLE_SID%_analyse
#  <esc>:wq
#
###############################################################################
ANALYZE_SCRIPT=%ORACLE_BASE%/bin/%ORACLE_SID%_analyse.ksh

echo "Creating daily analyse job"

[[ ! -d %ORACLE_BASE%/bin ]] && mkdir -p %ORACLE_BASE%/bin
if [[ ! -d %ORACLE_BASE%/bin ]]; then
  echo "Could not create the directory %ORACLE_BASE%/bin."
  exit 1
fi
rm -f ${ANALYZE_SCRIPT}

cat >> ${ANALYZE_SCRIPT} <<-!
#!/bin/bash
###############################################################################
#  DESCRIPTION:
#  This script analyses all the tables in the following schemas on the
#  %ORACLE_SID% instance:
#  %APPLICATION_SCHEMAS%
#
#  PREPARATION:
#  1. This script can be run from any directory.
#  2. This script should be executable. If unsure, type:
#     chmod +x %ORACLE_SID%_analyse
#  3. This script should be run as the Oracle Admin. user. This user is usually
#     configured as oracle:oinstall.
#
#  USAGE:
#  Ideally, this script should be run in a regular basis.
#  This can be implemented by adding it to a Oracle Admin's crontab:
#  As user oracle:
#  $ crontab -e
#  i (for insert mode)
#  10 0 * * * %ORACLE_BASE%/bin/%ORACLE_SID%_analyse
#  <esc>:wq
###############################################################################
!

cat >> ${ANALYZE_SCRIPT} <<-!
sqlplus -s / as sysdba <<EOF
set linesize 10000
set arraysize 1
set feedback off
set pagesize 0
set verify off
set termout off
!

sqlplus -s / as sysdba >> ${ANALYZE_SCRIPT} <<- !
set linesize 10000
set arraysize 1
set feedback off
set pagesize 0
set verify off
set termout off
select 'ANALYZE TABLE '||owner||'.'||table_name||' ESTIMATE STATISTICS SAMPLE 10 PERCENT;'||chr(10)||
       'ANALYZE TABLE '||owner||'.'||table_name||' ESTIMATE STATISTICS FOR ALL INDEXES;'||chr(10)||
       'ANALYZE TABLE '||owner||'.'||table_name||' ESTIMATE STATISTICS FOR ALL INDEXED COLUMNS;'
  from sys.dba_tables
 where owner not in ('SYS','SYSTEM','SYSMAN','XDB')
   and table_name <> 'PLAN_TABLE'
   and table_name not like '%_MAP_%'
   and table_name not like '%_IOT_%'
   and table_name not like '%$%'
   and table_name not like '%/%'
   and instr('%APPLICATION_SCHEMAS%',owner)>0;
!


cat >> ${ANALYZE_SCRIPT} <<-!
EOF
###############################################################################
# END OF FILE
###############################################################################
!

chmod +x ${ANALYZE_SCRIPT}

# Add this to contab. This will remove all comments from the crontab
(crontab -l | grep -v ${ANALYZE_SCRIPT} | grep -v '^#'; echo "10 0 * * * ${ANALYZE_SCRIPT}")|crontab

echo "Table analysis will run daily at 10 minutes past midnight."
echo "You can modify user %ORACLE_OWNER%'s crontab entry to change"
echo "the time if it does not suit you using the following command:"
echo "  \$ export EDITOR=nano"
echo "  \$ crontab -e"
echo "\n"

exit 0

###############################################################################
# END OF FILE
###############################################################################





