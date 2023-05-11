#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -o nounset

# GLOBAL CONSTANTS
declare -r SCRIPT_AUTHOR="Cedric OBEJERO <cedric.obejero@tanooki.fr>"
declare -r SCRIPT_RELEASE="0.1.1"
declare -r SCRIPT_DATE="May 4th, 2023"
declare -r SCRIPT_PATH=$( cd $(dirname ${BASH_SOURCE[0]}) > /dev/null; pwd -P )

declare -r LOGDIR="/var/log/$(basename $0)"
declare -r LOGFILE="${LOGDIR}/setup.log"

# COMMON FUNCTIONS
function error() { echo -e "[\e[31m  ERROR  \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${LOGFILE}; }
function warn()  { echo -e "[\e[33m WARNING \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${LOGFILE}; }
function info()  { echo -e "[\e[32m  INFO   \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${LOGFILE}; }

function usage() {
  cat <<EOF

Usage: $0

NAME
      $(basename $0) - apply hardening rules upon system components

SYNOPSIS
      $(basename $0) [OPTION]... [LEVEL]...

DESCRIPTION
      Apply security rules and values to the kernel and system features. Accept only the
      following values as security levels: Basics (1 as default), Secured (2) and Paranoid (3)

      -l
          Define security level to be applied, requiring integer values [1-3]

      -h
          Display current help information

      -v
          Display current release of the user command

AUTHOR
      ${SCRIPT_AUTHOR}

NOTES
      $(basename $0) ${SCRIPT_RELEASE}
      ${SCRIPT_DATE}

EOF
}

function show_release() {
	cat <<EOF
$(basename $0) ${SCRIPT_RELEASE} (${SCRIPT_DATE})

EOF
}

function check_root() {
	if [[ "$(id -u)" -ne 0 ]]; then
		echo "This script MUST be run as ROOT" >&2
		exit 1
	else
		echo "Access privileges validated"
	fi
}

function check_logfile() {
	[ ! -d ${LOGDIR} ] && { mkdir ${LOGDIR}; chown root:root ${LOGDIR}; chmod 775 ${LOGDIR}; }
	[ ! -f ${LOGFILE} ] && { touch ${LOGFILE}; chown root:root ${LOGFILE}; chmod 664 ${LOGFILE}; }
}

function check_level() {
  echo "Security Level passed is '$1'"
	if ! [[ $1 =~ '^[1-3]$' ]]; then
    echo 'Required security level argument not valid' >&2;
    echo 'Use option -h for more details';
    exit 1
  fi
}

#function harden_os() {
#	warn "${FUNCNAME[0]} - To be completed"
#}

function main() {

  # the optional parameters string starting with ':' for silent errors snd h for help usage
  local -r OPTS=':hvl:'
  local LEVEL=1

  while builtin getopts ${OPTS} opt "${@}"; do
      case $opt in
	  	h)
				usage;
				exit 0
	    	;;
			v)
				show_release;
				;;
			l)
				LEVEL=${OPTARG}
				check_root
        check_logfile
				check_level ${OPTARG}
#				harden_os
				;;
     	:)
	      echo 'required argument not found for option -'${OPTARG} >&2;
			  echo 'Use option -h for more details';
	      exit 1
	      ;;
      *)
				echo 'Unknown option - '${OPTARG} >&2;
				usage;
				exit 128
        ;;
      esac
  done

  exit 0
}

main "$@"
