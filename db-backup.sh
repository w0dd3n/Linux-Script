!/bin/bash

###
# Script to backup one node of Galera cluster
# Basic method using mysqldump is proposed
# Advanced approch should use mariabackup tool
# Script will generate archive and checksum 
# and then transfert file to remote backup server
# To be scheduled with CRONTAB of dedicated service user
#
# N.B. Create dedicated user for CRONTAB and BACKUP_LOG access
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
declare -r BACKUP_DIR=${TMP_FILE_PREFIX}/
declare -r OPT_CHECKSUM_LIST="sha1 sha256 sha384 sha512"
declare -r BACKUP_LOG="/var/log/$SCRIPT_NAME.log"
declare -r NAS_HOST="nas.tanooki.fr"
declare -r NAS_USER="mscyber-form"
declare -r NAS_USER_KEY="/var/lib/backup-script/.ssh/id_ecdsa"
declare -r NAS_HOMEDIR="/home/mscyber-form"

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

        #req_progs mysql mysqldump date sha1sum sha256sum sha384sum sha512sum
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

function check_backup_dir() {
        log_dbg "ENTER - check_backup_dir()"

        if [[ ! -d ${BACKUP_DIR} || ! -r ${BACKUP_DIR} ]]; then
                log_err "Not a directory or access denied to ${BACKUP_DIR}"
                return  2
        else
                backup_files=$(find "${BACKUP_DIR}" -type f)
                for file in $backup_files; do
                        if [ ! -r ${BACKUP_DIR} ]; then
                                return 5
                        fi
                done
        fi
        return 0
}

function collect_data() {
        log_dbg "ENTER - collect_data()"

        # TODO - mysql -u root -ppassword --execute "SET wsrep desync = ON"

        # TODO - mysqldump -p -u admin_backup --flush-logs --all-databases > ${TMP_FILE_PREFIX}.${backup_date}.sql

        # TODO - cp /etc/my.conf ${TMP_FILE_PREFIX}/etc/my.cnf
        # TODO - cp /etc/mysql/mariadb.conf.d/60-galera.cnf ${TMP_FILE_PREFIX}/etc/mysql/mariadb.conf.d/60-galera.cnf

        local backup_date=$(date --iso-8601=second --utc | tr -d "\-\:\+")
        tar --create --gzip --absolute-names \
            --same-permissions --same-owner \
            --file ${TMP_FILE_PREFIX}.${backup_date}.tar.gz ${BACKUP_DIR}
        if [ $? -ne 0 ]; then
                log_err "Failed to create backup archive - error code: $?"
                cleanup
                return 5
        else
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

        -f, --file
                Path to website files to backup, defautl to /var/www/html

        -h, --help
                Display this manual page

        -v, --version
                Display script release number

RETURN CODES
        0       Script executed without error - ERR_NOERROR

        1       Usage error, syntax or files provided in option

        2       No such file or directory, see FILES section for more

        5       I/O Error using file system or not readable files

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
        local -r OPTS=':f:c:hv'

        check_required_programs "mysql mysqldump date sha1sum sha256sum sha384sum sha512sum"

        while builtin getopts ${OPTS} opt "${@}"; do
                case $opt in
                        f)
                                BACKUP_DIR="$OPTARG";
                                ;;
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

        check_backup_dir ${BACKUP_DIR}
        if [ $? -ne 0 ]; then
                log_err "Invalid directory to backup ${BACKUP_DIR}"
                exit 2
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
