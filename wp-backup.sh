#!/bin/bash

###
# Script to backup Wordpress website
# Script will generate archive and checksum 
# and then transfert file to remote backup server
#
# N.B. Create dedicated user for CRONTAB and BACKUP_LOG access
#
# Author - Cedric OBEJERO <cedric.obejero@tanooki.fr>
# Date   - July 2024
##

# Exit immediatly if a command exits with a non-zero status
set -o nounset

# SECTION - Global constants
declare -r SCRIPT_NAME="wp-backup"
declare -r SCRIPT_VERSION="V0R1"
declare -r SCRIPT_PATH=$( cd $(dirname ${BASH_SOURCE[0]}) > /dev/null; pwd -P )
declare -r TMP_FILE_PREFIX=${TMPDIR:-/tmp}/$SCRIPT_NAME
declare -r OPT_CHECKSUM_LIST="sha1 sha256 sha384 sha512"
declare -r BACKUP_LOG="/var/log/$SCRIPT_NAME.log"

# SECTION - Globales for default script values
declare DEBUG_MODE=0
declare CHECKSUM_OPT="sha256"
declare BACKUP_DIR="/var/www/html"

# SECTION - Functions

function log_err() { echo -e "[ ERR ] - $(date --rfc-3339=seconds) - $1" | tee -a ${BACKUP_LOG}; }
function log_wrn() { echo -e "[ DBG ] - $(date --rfc-3339=seconds) - $1" | tee -a ${BACKUP_LOG}; }
function log_inf() { echo -e "[ INF ] - $(date --rfc-3339=seconds) - $1" | tee -a ${BACKUP_LOG}; }
function log_dbg() { if [ ${DEBUG_MODE} == 1 ]; then echo -e "[ DBG ] - $(date --rfc-3339=seconds) - $1" | tee -a ${BAC>

# TODO - Rotate logs

function check_required_programs() {
        #req_progs date sha1sum sha256sum sha384sum sha512sum
        for prog in ${@}; do
                hash "${prog}" 2>&- || \
                        { log_err "Required program \"${prog}\" not installed nor in search PATH.";
                          exit 65;
                        }
        done
}

function check_hash_option() {
        for sum in ${OPT_CHECKSUM_LIST}; do
                if [ "$sum" = "$1" ]; then
                        return 0;
                fi
        done
        return 1;
}

function check_backup_dir() {
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
#       log_wrn "${FUNCNAME} - to be implemented - ARGS : ${BACKUP_DIR}"

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
                                echo -e "SHA160==$(sha1sum ${TMP_FILE_PREFIX}.${backup_date}.tar.gz)" > ${TMP_FILE_PREF>
                                ;;
                        sha256)
                                echo -e "SHA256==$(sha256sum ${TMP_FILE_PREFIX}.${backup_date}.tar.gz)" > ${TMP_FILE_PR>
                                ;;
                        sha384)
                                echo -e "SHA384==$(sha384sum ${TMP_FILE_PREFIX}.${backup_date}.tar.gz)" > ${TMP_FILE_PR>
                                ;;
                        sha512)
                                echo -e "SHA512==$(sha512sum ${TMP_FILE_PREFIX}.${backup_date}.tar.gz)" > ${TMP_FILE_PR>
                                ;;
                esac
                log_inf "SUCCESS - Backup archive and checksum created"
        fi

        return 0;
}

function transfer_data() {
        log_wrn "${FUNCNAME} - to be implemented"
        exit 0;
}

function cleanup() {
        log_inf "Cleaning up temporary files and cached data"
        rm -f ${TMP_FILE_PREFIX}.*
}

function show_version() {
        echo "${SCRIPT_NAME} under release ${SCRIPT_VERSION}"
}

function usage() {
more <<EOF
NAME
        wp-backup - Automation script to create and export backup archive of wordpress websites

SYNOPSYS
        wp-backup [OPTIONS]

DESCRIPTION
        wp-backup is a BASH Script provided to automate schedule backup tasks

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
        /usr/local/bin/wp-bakup.sh
                Default location to store the script

        /tmp/wp-backup.*
                Default location for temporary files generated during operations

        /var/log/wp-backup.log
                Default location for activities and debug logs

HISTORY
        v0r1 - July, 8th 2024 - Cedric OBEJERO <cedric.obejero@tanooki.fr>


EOF
}

# SECTION - Main entrance
function main() {
        local -r OPTS=':f:c:hv'

        check_required_programs "date sha1sum sha256sum sha384sum sha512sum"

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

#       cleanup

        exit 0
}

# set a trap for cleaning up the environment before process termination
trap "cleanup; exit 1" 1 2 3 13 15

# main executable function at the end of script
main "$@"
