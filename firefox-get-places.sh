#!/bin/bash

# SYNOPSIS
# Gather Firefox user`s data from places.sqlite file
# This file contains all Firefox bookmarks and lists
# of all the files downloaded and websites visited
#
# AUTHOR - Cedric OBEJERO <cedric.obejero@tanooki.fr>


# Exit immediately if a command exits with a non-zero status.
set -o nounset

### Global constants
declare -r SCRIPTPATH=$( cd $(dirname ${BASH_SOURCE[0]}) > /dev/null; pwd -P )
#declare -r TMP_FILE_PREFIX=${TMPDIR:-/tmp}/prog.${BASH_SOURCE[0]}
declare -r TMP_FILE_PREFIX=${TMPDIR:-/tmp}/prog.$$
declare -r MAIN_LOGFILE=${TMP_FILE_PREFIX}.$(date --iso-8601=seconds).log

### Logging levels 
###
function error() { echo -e "[\e[31m  ERROR  \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${MAIN_LOGFILE}; }
function warn()  { echo -e "[\e[33m WARNING \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${MAIN_LOGFILE}; }
function info()  { echo -e "[\e[32m  INFOS  \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${MAIN_LOGFILE}; }
function blog()  { echo -e " $1" | tee -a ${MAIN_LOGFILE}; }

### Log header
function log_header()
{
  blog "*************************************************************"
  blog "** Firefox Websites history gathering "
  blog "** Date: $(date -R)"
  blog "** Started: $0 $*"
}

### Log footer
function log_footer()
{
  blog "** Date: $(date -R)"
  blog "** End Of File"
  blog "**************************************************************"
}

### Check that required apps are available on device
### Args:
###   all progs need to be given as parameters
###   e.g. _check_required_programs md5 xsltproc
### Returns:
###  0 if succeeded 
###  1 otherwise log error message
function _check_required_programs() {
  # Required program(s)
  req_progs=(firefox sqlite3)
  for p in ${req_progs}; do
    if [[ "$(hash ${p})" -ne 0 ]]; then
	    error >&2 " Required program \"${p}\" not installed or in search PATH.";
      exit 1;
    else
      info "Required apps available"
    fi
  done
}

### Test script is executed as root.
### Args:
###   None
### Returns:
###   1 if not executed as root
function _check_root()
{
  if [[ "$(id -u)" -ne 0 ]]; then
    warn "This script must be run as root";
    exit 1
  else
    info "Root privileges validated";
  fi
}

### Locate all data history files of Firefox
### File places.sqlite is used in Firefox 3 and above
### See here for more : https://kb.mozillazine.org/Places.sqlite
### Args:
###   none
### Returns:
###   TODO
function _extract_places()
{
  local -r DB_PLACES_FILENAME="places.sqlite"
  local -r DB_HISTORY_QUERY="SELECT last_visit_date,url,title FROM moz_places;"
  local -r DB_OUTPUT_FILEPATH="${TMP_FILE_PREFIX}.firefox-history-$(date --iso-8601=minutes).log"

  places_files=( $(find /home -type f -name "places.sqlite" | grep ".mozilla")  )

  if [ ${#places_files[@]} -eq 0 ]; then
    error "No file has been found for `places.sqlite`"
  else
    for test_file in "${places_files[@]}"; do
      info "Gathering data from $test_file"
      cp "$test_file" "${TMPDIR:-/tmp}/$DB_PLACES_FILENAME"
      echo "### FILENAME - $test_file" > "$DB_OUTPUT_FILEPATH"
      echo "### DATE - $(date)" >> "$DB_OUTPUT_FILEPATH"
      echo "$DB_HISTORY_QUERY" | sqlite3 "${TMPDIR:-/tmp}/$DB_PLACES_FILENAME" >> "$DB_OUTPUT_FILEPATH"
      rm -f "${TMPDIR:-/tmp}/$DB_PLACES_FILENAME"
    done
  fi
}

function cleanup()
{
  rm -f ${TMP_FILE_PREFIX}.*
}

function usage()
{
  cat <<EOF

Usage: $0 [OPTION] [FILES]

 TODO - TO BE COMPLETED SOON ...
EOF
}


# Single function
function main() 
{
  # the optional parameters string starting with ':' for silent errors and h for help usage
  local -r OPTS=':h'

  while builtin getopts ${OPTS} opt "${@}"; do
    case $opt in
	    h)
        usage;
        exit 0
	      ;;
	    \?)
	      echo ${opt} ${OPTIND} 'is an invalid option' >&2;
	      usage;
	      exit ${INVALID_OPTION}
	      ;;
      :)
	      echo 'Required argument not found for option -'${OPTARG} >&2;
	      usage;
	      exit ${INVALID_OPTION}
	      ;;
      *) echo "Too many options. Can not happen actually :)"
        ;;
    esac
  done

  cleanup

  log_header
  _check_root
  _check_required_programs
  _extract_places
  log_footer

  exit 0
}

# set a trap for (calling) cleanup all stuff before process
# termination by SIGHUBs
trap "cleanup; exit 1" 1 2 3 13 15
# this is the main executable function at end of script
main "$@"

### EOF ###
