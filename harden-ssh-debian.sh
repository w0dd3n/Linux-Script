#!/bin/bash
# SSH Server Hardening Automation

## TODO - Handle SSH Key generation or import


### SHARED VARS
###
BASENAME=$(basename $0)
AUTHOR="Cedric OBEJERO <cedric.obejero@tanooki.fr>"
RELEASE="V2R1"
REL_DATE="Mar. 18th, 2023"

RST='\033[0;0m'
BOLD='\033[0;1m'
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[0;33m'

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_DIR="/etc/ssh/"
SSHD_BANNER="/etc/ssh/sshd-banner.txt"

HARDEN_SSHD=0
USAGE=0
VERSION=0

HARDEN_LOG="/var/log/harden-ssh.log"
function error() { echo -e "[\e[31m  ERROR  \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${HARDEN_LOG}; }
function warn()  { echo -e "[\e[33m WARNING \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${HARDEN_LOG}; }
function info()  { echo -e "[\e[32m  INFOS  \e[0m]-$(date --rfc-3339=seconds)-$1" | tee -a ${HARDEN_LOG}; }

### Arguments Handler
###
while [[ $# > 0 ]]; do
	ARG="$1"
	case $ARG in
	-s|--secure)
		HARDEN_SSHD=1
		;;
	-h|--help)
		USAGE=1
		;;
	-v|--version)
		VERSION=1
		;;
	*)
		error "Unknonw argument, aborting...\n\n"
		exit 128
		;;
	esac
	shift
done

usage() 
{
	printf "${BOLD}NAME${RST}\n"
	printf "	$BASENAME\n\n"
	printf "${BOLD}SYNOPSIS${RST}\n"
	printf "	$BASENAME [OPTIONS]\n\n"
	printf "${BOLD}DESCRIPTION${RST}\n"
	printf "	Harden security features from SSH Daemon Server\n"
	printf "	Following up ANSSI Security Guide Lines - http://ssi.gouv.fr\n\n"
	printf "	Mandatory arguments are as follow.\n\n"
	printf "	-s, --secure\n"
	printf "		WARNING - Must be executed with ROOT privileged\n"
	printf "		Apply security rules to harden SSHD service\n\n"
	printf " 	-h, --help\n"
	printf "		Display current help information\n\n"
	printf "	-v, --version\n"
	printf " 		Display command release informations\n\n"
}

show_version() 
{
	printf "${BOLD}NAME${RST}    $BASENAME\n"
	printf "${BOLD}AUTHOR${RST}  $AUTHOR\n"
	printf "${BOLD}RELEASE${RST} $RELEASE\n"
	printf "${BOLD}DATE${RST}    $REL_DATE\n"
}

function check_root()
{
    if [[ "$(id -u)" -ne 0 ]] ; then
        warn "This script must be run as root" >&2
        exit 1
    else
        info "Root privileges validated"
    fi
}

function check_sshd()
{
    info "Testing OpenSSH Server is installed..."
    if [[ $(dpkg-query -f '${binary:Package} - ${db:Status-Status}\n' -W | grep 'openssh-server' | grep 'installed' | wc -l) -eq 0 ]]; then
        warn "OpenSSH Server not installed - Processing with installation"
        apt update &>/dev/null
        apt install --yes --quiet --no-install-recommends openssh-server &>/dev/null
        if [[ $? -ne 0 ]]; then
            error "OpenSSH Server Installation FAILED"
            warn "Use this command for details : 'grep openssh-server /var/log/apt/term.log'"
            exit 1
        else
            info "OpenSSH Server Installation SUCCEDDED"
		fi
    fi

    systemctl enable openssh-server &>/dev/null
    if [[ $(systemctl is-active openssh-server) != "active" ]]; then
        error "Openssh Server Service is NOT RUNNING"
        warn "Use this command for details : 'journalctl -u openssh-server.service -b'"
        exit 1
    else
        info "OpenSSH Server is now INSTALLED and RUNNING"
    fi

    exit 0
}

harden_sshd() 
{
	info "Starting SSHD Server Hardening...\n"

	warn "Backup original config file"
	cp ${SSHD_CONFIG} ${SSHD_CONFIG}.$(date +"%y%m%d-%H%M%Z").bak

	info "ANSSI-R2 - Enforcing SSHD Release 2 only"
    sed -i "s/^.*Protocol.*$/Protocol 2/g" ${SSHD_CONFIG}
	
	info "Replacing port number by 666"
    sed -i "s/.*Port.*/Port 666/g" ${SSHD_CONFIG}

	info "Anonymize SSHD service banner"
	warn "Anonymization requires full re-install = ABORTING\n"

	info "Adding login banner message"	
	touch $SSHD_BANNER
	printf "" > $SSHD_BANNER
	printf "\n\n***************************************************\n" >> $SSHD_BANNER
	printf "\tWARNING Unauthorized access to this system\n" >> $SSHD_BANNER
	printf "\tis forbidden and will be prosecuted by law.\n" >> $SSHD_BANNER
	printf "\tBy accessing this system, you agree that your\n" >> $SSHD_BANNER
	printf "\tactions may be monitored if unauthorized usage\n" >> $SSHD_BANNER
	printf "\tis suspected by our organization\n" >> $SSHD_BANNER
	printf "***************************************************\n" >> $SSHD_BANNER
	printf "Banner $SSHD_BANNER\n" >> $SSHD_CONFIG
	sed -i 's/.*Banner.*/Banner ${SSHD_BANNER}/' $SSHD_CONFIG
	sed -i 's/.*PrintMotd.*/PrintMotd no/' $SSHD_CONFIG


	info "Enforce Privilege Execution Separation"
	sed -i 's/.*UsePrivilegeSeparation.*/UsePrivilegeSeparation sandbox/' $SSHD_CONFIG

	info "Enforce Restriction of user environnement"
	sed -i 's/.*PermitUserEnvironment.*/PermitUserEnvironment no/' $SSHD_CONFIG

	warn "Restrict number of active sessions = Max is 3 sessions"
	sed -i 's/.*MaxSessions.*/MaxSessions 3/' $SSHD_CONFIG

	info "Deny ROOT account usage"
	sed -i "s/^.*PermitRootLogin.*$/PermitRootLogin no/g" ${SSHD_CONFIG}

	info "Deny password authentication method"
	sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication no/' $SSHD_CONFIG
	sed -i 's/.*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' $SSHD_CONFIG
	sed -i 's/.*UsePAM.*/UsePAM no/' $SSHD_CONFIG

	info "Restrict to ECDSA or RSA server keypair usage"
	rm -f $SSHD_DIR/ssh_host_dsa*
	rm -f $SSHD_DIR/ssh_host_ed*

	## PREREQUISITE
	## Generate allowed users keypair as follow
	## ssh-keygen -t ecdsa -b 256 -C "email@company.com" -f id_ecdsa_USERNAME
	## Store keypair in $HOME/.ssh directory with chmod 700 on private keystore
	## Provide strong password to lock keystore
	## Copy Public Key to the SSHD Server
	## ssh-copy-id sshd_username@sshd_ip_address

	info "Prevent X11 Forwading - Graphical Interface Denial"
	sed -i 's/.*X11Forwarding.*/X11Forwarding no/' $SSHD_CONFIG

	info "Prevent TCP Forwarding on server"
	sed -i 's/.*AllowTcpForwarding.*/AllowTcpForwarding no/' $SSHD_CONFIG

	warn "ANSSI-R15 - Restrict allowed crypto algorithms"
    printf "Ciphers aes256-ctr,aes192-ctr,aes128-ctr\n" >> $SSHD_CONFIG
	printf "MACs hmac-sha2-512,hmac-sha2-256\n" >> $SSHD_CONFIG

	info "Enforcing enhanced logging of SSH Server activities"
	sed -i 's/.*PrintLastLog.*/PrintLastLog yes/' $SSHD_CONFIG
	sed -i 's/.*SyslogFacility.*/SyslogFacility AUTH/' $SSHD_CONFIG
	sed -i 's/.*LogLevel.*/LogLevel INFO/' $SSHD_CONFIG

	printf "[${GRN}INFO${RST}] - Reload configuration of OpenSSH Server"
    systemctl restart openssh-server
	if [ $? != 0 ]; then
		error "FAILED TO APPLY SECURITY CONFIG\n\n"
        warn "Use this command for details : 'journalctl -u openssh-server.service -b'"
	else 
		info "SSHD Server is now SECURE - See ya space cowboy !"
	fi
}

if [[ $USAGE = 1 ]]; then
	usage
	exit 1
elif [[ $VERSION = 1 ]]; then
	show_version
	exit 1
elif [[ $HARDEN_SSHD = 1 ]]; then
    check_root
	check_sshd
	harden_sshd
	exit 1
else 
	error "Invalid argument. See help for more details.\n"
	exit 128
fi

### EOF ###
