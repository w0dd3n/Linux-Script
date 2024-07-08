!/bin/bash

###
# Script to backup Wordpress website - wp-form
# Script will generate archive and checksum 
# and then transfert file to remote backup server
#
# Date   - July 2024
##

# Exit immediatly if a command exits with a non-zero status
set -o nounset

# SECTION - Global constants
declare -r SCRIPT_NAME="wp-backup"
declare -r SCRIPT_VERSION="V0R1"
declare -r SCRIPT_PATH=$( cd $(dirname ${BACH_SOURCE[0]}) > /dev/null; pwd -P )
declare -r TMP_FILE_PREFIX=${TMPDIR:-/tmp}/$SCRIPT_NAME.$$

declare -r ERR_NOERROR=0
declare -r ERR_NOENT=1
declare -r ERR_IO=5
declare -r ERR_NOPKG=65
declare -r ERR_PROTO=71
declare -r ERR_NETDOWN=100
declare -r ERR_NETUNREACH=101
declare -r ERR_CONNRESET=104

# SECTION - Functions
function check_required_programs() {
        req_progs(date sha1sum sha256sum sha384sum sha512sum)
        for prog in ${@}; do
                hash "${prog}" 2>&- || \
                        { echo >&2 "Required program \"${prog}\" not installed nor in search PATH.";
                          exit ERR_NOPKG;
                        }
        done
}

function cleanup() {
        rm -f ${TMP_FILE_PREFIX}.*
}

function show_version() {
        echo ${SCRIPT_NAME} under release ${SCRIPT_VERSION}"
}

function usage() {
cat <<EOF
NAME
        wp-backup - Automation script to create and export backup archive of wordpress websites

SYNOPSYS
        wp-backup [OPTIONS] 

DESCRIPTION
        wp-backup is a BASH Script provided to automate schedule backup tasks

OPTIONS
        -c, --checksum [sha1 | sha256 | sha384 | sha512]
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

        5       I/O Error using file system

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
        local -r OPTS=':chv'

        while builtin getopts ${OPTS} opt "${@}"; do
                case $opt in
                        c)
                                echo "TODO - Complete checksum";
                                exit ERR_NOERROR;
                                ;;
                        h)
                                usage;
                                exit ERR_NOERROR;
                                ;;
                        v)
                                show_version;
                                exit ERR_NOERROR;
                                ;;
                        \?)
                                echo ${opt} ${OPTIND} 'is an invalid option' >&2;
                                usage;
                                exit ERR_NOENT;
                                ;;
                        *)
                                echo "Too many options. Cannot happen actually !";
                                usage;
                                exit ERR_NOENT;
                                ;;
                esac
        done

        cleanup

        exit ERR_NOERROR
}

# set a trap for cleaning up the environment before process termination
trap "cleanup; exit 1" 1 2 3 13 15

# main executable function at the end of script
main "$@"
