#!/bin/sh
##
## Sample PE database migration script.
## It does make certain assumptions.
## Josh Beard
## https://github.com/joshbeard
##
DBROOT=$(awk -F = '/q_puppet_enterpriseconsole_database_root_password/{print $2}' \
  /etc/puppetlabs/installer/database_info.install)

PE2_DATABASES="console console_auth console_inventory_service"
PE3_DATABASES="console console_auth pe-puppetdb"

PE_VERSION=$(/opt/puppet/bin/facter -p pe_version)

ACTION="$1"

for i in "$@"
do
  case $i in
    -r|--ignore-reports*)
      IGNORE_REPORTS=true
      shift
      ;;
    *)
      # unknown option
      ;;
  esac
done

## Usage
if [ -z "$1" ]; then
  echo "Usage: $0 [import|export]"
  exit 0
fi

## Some sanity checks
if [ "$(whoami)" != "root" ]; then
  echo "You must be root to run this."
  exit 1
fi

if [ -z "$PE_VERSION" ]; then
  echo "Could not get the PE version via Facter"
  echo "(/opt/puppet/bin/facter -p pe_version)"
  exit 1
fi


## Which databases for this PE version
if [[ "$PE_VERSION" == 2.?.? ]]; then
  if [ -z "$DBROOT" ]; then
    echo "The database root password must be set."
    exit 1
  fi
  DATABASES="$PE2_DATABASES"
elif [[ "$PE_VERSION" == 3.?.? ]]; then
  DATABASES="$PE3_DATABASES"
fi

## Function for exporting databases
function export_db() {
for db in $DATABASES; do
  echo "Dumping ${db} to ./${db}.sql..."
  if [[ "$PE_VERSION" == 2.?.? ]]; then
    if [ "$IGNORE_REPORTS" == 'true' ]; then
      EXT_OPTS="--ignore-table=console.reports --ignore-table=console.report_logs --ignore-table=console.old_reports"
    fi
    /usr/bin/mysqldump -u root --password=${DBROOT} ${EXT_OPTS} ${db} > ${db}.sql
  elif [[ "$PE_VERSION" == 3.?.? ]]; then
    su - pe-postgres -s /bin/bash -c \
      "/opt/puppet/bin/pg_dump -Fc -p 5432 ${db}" > ${db}.sql
  fi
done
}

## Function for importing databases
function import_db() {
for db in $DATABASES; do
  echo "Restoring ${db} from ./${db}.sql..."
  if [[ "$PE_VERSION" == 2.?.? ]]; then
    /usr/bin/mysql -u root --password=${DBROOT} ${db} < ${db}.sql
  elif [[ "$PE_VERSION" == 3.?.? ]]; then
    su - pe-postgres -s /bin/bash -c \
      "/opt/puppet/bin/pg_restore -Fc -c -d ${db} -p 5432 ${PWD}/${db}.sql"
  fi
done
}

echo "========================================================================"
echo "Database migration for PE version ${PE_VERSION}"
echo
if [ "$IGNORE_REPORTS" == 'true' ]; then
  echo "**** REPORTS WILL NOT BE EXPORTED ****"
fi
echo "This will dump/restore the databases to/from the current working directory"
echo

if [ "$ACTION" == 'export' ]; then
  export_db "$PE_VERSION"
elif [ "$ACTION" == "import" ]; then
  import_db "$PE_VERSION"
fi

echo "Complete!"
