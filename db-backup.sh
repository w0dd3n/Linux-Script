#!/bin/bash

###
# Script to backup one node of Galera cluster - mysqldump basic method
# Advanced approch should use mariabackup for performance purposes
# Script will generate archive and checksum
# and then transfert file to remote backup server
# To be scheduled with CRONTAB of dedicated service user
#
# N.B. Create dedicated service user for CRONTAB and BACKUP_LOG access
#
# Date   - July 2024
##

# Exit immediatly if a command exits with a non-zero status
set -o nounset

# SECTION - Global constants
declare -r SCRIPT_NAME="db-backup"
declare -r SCRIPT_VERSION="V0R1"
declare -r SCRIPT_PATH=$( cd $(dirname ${BASH_SOURCE[0]}) > /dev/null; pwd -P )

declare -r TMP_FILE_PREFIX=${TMPDIR:-/tmp}/$SCRIPT_NAME

declare -r OPT_CHECKSUM_LIST="sha1 sha256 sha384 sha512"
declare -r BACKUP_LOG="/var/log/$SCRIPT_NAME.log"

declare -r NAS_HOST="nas.tanooki.fr"
declare -r NAS_USER="mscyber-form"
declare -r NAS_USER_KEY="/var/lib/backup-script/.ssh/id_ecdsa"
declare -r NAS_HOMEDIR="/home/mscyber-form"

# TODO - Upgrade usage with Key Vault like Harshicorp Vault
declare -r DB_BACKUP_USER="admin_backup"
declare -r DB_BACKUP_PWD="password"
declare -r DB_ADMIN_USER="root"
declare -r DB_ADMIN_PWD="password"
declare -r DB_HOST="localhost"
declare -r DB_PORT="3306"
declare -r DB_NAME="wordpress"

# Apply before execute
# $ ssh-keygen -b 256 -t ecdsa
# $ chmod 600 /var/lib/backup-script/.ssh/id_ecdsa
# $ chmod 644 /var/lib/backup-script/.ssh/id_ecdsa.pub
# Copy id_ecdsa.pub content to .ssh/authrorized_key on backup server

# SECTION - Globales for default script values
declare DEBUG_MODE=0
declare CHECKSUM_OPT="sha256"

# SECTION - Functions

function log_err() { echo -e "[ ERR ] - $(date --rfc-3339=seconds) - $1" | tee -a ${BACKUP_LOG} &> /dev/null; }
function log_wrn() { echo -e "[ DBG ] - $(date --rfc-3339=seconds) - $1" | tee -a ${BACKUP_LOG} &> /dev/null; }
function log_inf() { echo -e "[ INF ] - $(date --rfc-3339=seconds) - $1" | tee -a ${BACKUP_LOG} &> /dev/null; }
function log_dbg() { if [ ${DEBUG_MODE} == 1 ]; then echo -e "[ DBG ] - $(date --rfc-3339=seconds) - $1" | tee -a ${BACKUP_LOG} &> /dev/null; }

# TODO - Rotate logs

function check_required_programs() {
        log_dbg "ENTER - check_required_programs()"

        #req_progs mysql mysqldump tar scp date sha1sum sha256sum sha384sum sha512sum
        for prog in ${@}; do
                hash "${prog}" 2>&- || \
                        { log_err "Required program \"${prog}\" not installed nor in search PATH.";
                          exit 65;
                        }
        done
}

function check_hash_option() {
        log_dbg "ENTER - check_hash_option()"

        for sum in ${OPT_CHECKSUM_LIST}; do
                if [ "$sum" = "$1" ]; then
                        return 0;
                fi
        done
        return 1;
}

function check_db_access() {
        log_dbg "ENTER - check_db_access()"

        mysql   --host ${DB_HOST} --port ${DB_PORT} \
                --user ${DB_BACKUP__USER} --password${DB_BACKUP_PWD} \
                ${DB_NAME} --execute "SELECT 1;" 2>&1 /dev/null
        case $? in
                1)    log_err "Failed to connect to database server"; return 1 ;;
                1045) log_err "Authentication failed. Check username and password."; return 7 ;;
                1049) log_err "Unknown database. Check database logs for more."; return 7 ;;
                *)    log_err "Unknown error: $? - Check database logs for more."; return 1 ;;
        esac

        return 0
}

function collect_data() {
        log_dbg "ENTER - collect_data()"

        local -r backup_date=$(date --iso-8601=second --utc | tr -d "\-\:\+")

        log_inf "Prepare node for backup - Desinchronizing WSREP"
        rc_value=$(mysql --user ${DB_ADMIN} --password${DB_ADMIN_PWD} --execute "SET wsrep_desync = ON" 2>&1)
        if [ $? -ne 0 ]; then
                log_err $rc_value
                return 7
        fi

        log_inf "Dumping content of all databases ..."
        mysqldump --user ${DB_BACKUP_USER} --password${DB_BACKUP_PWD} \
                  --flush-logs --all-databases > ${TMP_FILE_PREFIX}.${backup_date}.sql
        if [ $? -ne 0 ]; then 
                log_err "Failed dump of databases - Error code: $?"
                return 7
        fi

        log_inf "Databases extract finalized - Restore node WSREP synchronization"
        rc_value=$(mysql --user ${DB_ADMIN} --password${DB_ADMIN_PWD} --execute "SET wsrep_desync = OFF" 2>&1)
        if [ $? -ne 0 ]; then
                log_err $rc_value
                return 7
        fi

        cp /etc/my.conf ${TMP_FILE_PREFIX}.${backup_date}.my.cnf
        cp /etc/mysql/mariadb.conf.d/60-galera.cnf ${TMP_FILE_PREFIX}.${backup_date}.60-galera.cnf

        tar --create --gzip --absolute-names \
            --same-permissions --same-owner \
            --file ${TMP_FILE_PREFIX}.${backup_date}.tar.gz ${TMP_FILE_PREFIX}.*.sql ${TMP_FILE_PREFIX}.*.cnf
        if [ $? -ne 0 ]; then
                log_err "Failed to create backup archive - error code: $?"
                return 5
        else
                # IMPORTANT - First check value with check_hash_option()
                case ${CHECKSUM_OPT} in
                        sha1)
                                echo -e "SHA160==$(sha1sum ${TMP_FILE_PREFIX}.${backup_date}.tar.gz)" > ${TMP_FILE_PREFIX}.${backup_date}.checksum
                                ;;
                        sha256)
                                echo -e "SHA256==$(sha256sum ${TMP_FILE_PREFIX}.${backup_date}.tar.gz)" > ${TMP_FILE_PREFIX}.${backup_date}.checksum
                                ;;
                        sha384)
                                echo -e "SHA384==$(sha384sum ${TMP_FILE_PREFIX}.${backup_date}.tar.gz)" > ${TMP_FILE_PREFIX}.${backup_date}.checksum
                                ;;
                        sha512)
                                echo -e "SHA512==$(sha512sum ${TMP_FILE_PREFIX}.${backup_date}.tar.gz)" > ${TMP_FILE_PREFIX}.${backup_date}.checksum
                                ;;
                esac
                log_inf "SUCCESS - Backup archive and checksum created"
        fi

        return 0;
}

function transfer_data() {
        log_dbg "ENTER - transfer_data()"

        local -r rate_limit=1000        # kbps

        scp -q -l $rate_limit -i ${NAS_USER_KEY} ${TMP_FILE_PREFIX}.* ${NAS_USER}@${NAS_HOST}:${NAS_HOMEDIR}
        if [ $? -ne 0 ]; then
                return 71
        fi

        return 0;
}

function cleanup() {
        log_dbg "ENTER - cleanup()"

        rm -f ${TMP_FILE_PREFIX}.*
}

function show_version() {
        log_dbg "ENTER - show_version()"

        echo "${SCRIPT_NAME} under release ${SCRIPT_VERSION}"
}

function usage() {
more <<EOF
NAME
        db-backup - Automation script to create and export backup archive of Galera Cluster

SYNOPSYS
        db-backup [OPTIONS]

DESCRIPTION
        db-backup is a BASH Script provided to automate scheduled backup tasks

OPTIONS
        -c, --checksum [ sha1 | sha256 | sha384 | sha512 ]
                Define message digest algorithm to be used, default as SHA-256

        -d, --debug
                Display and log debugging messages

        -h, --help
                Display this manual page

        -v, --version
                Display script release number

RETURN CODES
        0       Script executed without error - ERR_NOERROR

        1       Usage error, syntax or files provided in option

        2       No such file or directory, see FILES section for more

        5       I/O Error using file system or not readable files

        7       Database access failed

        65      Required package not available

        71      Protocol error during backup server synchronization

        100     Network is down

        101     Target server is unreachable

        104     Connection reset by peer

FILES
        /usr/local/bin/db-bakup.sh
                Default location to store the script

        /tmp/db-backup.*
                Default location for temporary files generated during operations

        /var/log/db-backup.log
                Default location for activities and debug logs

HISTORY
        v0r1 - July, 10th 2024 


EOF
}

# SECTION - Main entrance
function main() {
        local -r OPTS=':c:dhv'

        check_required_programs "mysql mysqldump tar scp date sha1sum sha256sum sha384sum sha512sum"

        while builtin getopts ${OPTS} opt "${@}"; do
                case $opt in
                        c)
                                CHECKSUM_OPT="$OPTARG";
                                ;;
                        d)
                                DEBUG_MODE=1
                                ;;
                        h)
                                usage;
                                exit 0;
                                ;;
                        v)
                                show_version;
                                exit 0;
                                ;;
                        \?)
                                echo ${opt} ${OPTIND} 'is an invalid option' >&2;
                                usage;
                                exit 1;
                                ;;
                        *)
                                echo "Invalid option or argument";
                                usage;
                                exit 1;
                                ;;
                esac
        done

        check_hash_option ${CHECKSUM_OPT}
        if [ $? -ne 0 ]; then
                log_err "Invalid checksum option ${CHECKSUM_OPT}"
                exit 1
        fi

        check_db_access
        if [ $? -ne 0 ]; then
                log_err "Failed to access database for backup ops"
                exit 7
        fi

        collect_data
        if [ $? -ne 0 ]; then
                log_err "Cannot build up archive of backup from ${BACKUP_DIR}"
                cleanup
                exit 5
        fi

        transfer_data
        if [ $? -ne 0 ]; then
                log_err "Failed to upload backup data"
                cleanup
                exit 101
        fi

        cleanup

        exit 0
}

# set a trap for cleaning up the environment before process termination
trap "cleanup; exit 1" 1 2 3 13 15

# main executable function at the end of script
main "$@"

