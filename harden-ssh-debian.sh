#!/bin/bash
# SSH Server Hardening Automation

## PREREQUISITE
## Generate allowed users keypair as follow
## ssh-keygen -t ecdsa -b 256 -C "email@company.com" -f id_ecdsa_USERNAME
## Store keypair in $HOME/.ssh directory with chmod 700 on private keystore
## Provide strong password to lock keystore
## Copy Public Key to the SSHD Server before hardening configuration
## ssh-copy-id sshd_username@sshd_ip_address

## TODO - Setup with FAIL2BAN
## TODO - Setup UFW package and configure with SSH Port Listening


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

function custom_update()
{
	info "Updating local system packages"
	apt update &>/dev/null
	apt upgrade &>/dev/null
	if [[ $? -ne 0 ]]; then
		error "System full upgrade FAILED"
		warn "Use this command for details : 'tail -f /var/log/apt/term.log'"
		exit 1
	else
		info "Full System Upgrade DONE"
	fi

	info "Custom Packages Installation"
	apt --yes --quiet --no-install-recommends install \
#		ufw fail2ban \
		htop lsb-release unattended-upgrades \
		secure-delete net-tools dnsutils &>/dev/null
	if [[ $? -ne 0 ]]; then
		error "Custom packages installation FAILED"
		warn "Use this command for details : 'tail -f /var/log/apt/term.log'"
		exit 1
	else
		info "Custome packages installation DONE"
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

    systemctl enable ssh &>/dev/null
    if [[ $(systemctl is-active ssh) != "active" ]]; then
        error "Openssh Server Service is NOT RUNNING"
        warn "Use this command for details : 'journalctl -u openssh-server.service -b'"
        exit 1
    else
        info "OpenSSH Server is now UP and RUNNING"
    fi
}

harden_sshd() 
{
	info "Starting SSHD Server Hardening..."

	warn "Backup original config file"
	cp ${SSHD_CONFIG} ${SSHD_CONFIG}.$(date +"%y%m%d-%H%M%Z").bak

	info "Enforcing SSHD Release 2 only"
    sed -i "s/^.*Protocol.*$/Protocol 2/" ${SSHD_CONFIG}
	
	info "Replacing port number by 666"
    sed -i "s/.*Port.*/Port 666/" ${SSHD_CONFIG}

	info "Anonymize SSHD service banner"
	warn "Anonymization requires full re-install = ABORTING"
	warn "Customizing service banner"
	sed -i "s/.*VersionAddendum.*/VersionAddendum 'RESTRICTED'/g" ${SSHD_CONFIG}

	info "Adding login banner message"	
	touch ${SSHD_BANNER}
	printf "" > ${SSHD_BANNER}
	printf "\n***************************************************\n" >> ${SSHD_BANNER}
	printf " !!! WARNING !!! Unauthorized access to this system\n" >> ${SSHD_BANNER}
	printf " is forbidden and will be prosecuted by law.\n" >> ${SSHD_BANNER}
	printf " By accessing this system, you agree that your\n" >> ${SSHD_BANNER}
	printf " actions may be monitored if unauthorized usage\n" >> ${SSHD_BANNER}
	printf " is suspected by our organization\n" >> ${SSHD_BANNER}
	printf "***************************************************\n" >> ${SSHD_BANNER}
	sed -i -r "s/.*Banner.*/Banner ${SSHD_BANNER}/g" ${SSHD_CONFIG}
	sed -i 's/.*PrintMotd.*/PrintMotd no/' ${SSHD_CONFIG}


	info "Enforce Privilege Execution Separation"
	sed -i 's/.*UsePrivilegeSeparation.*/UsePrivilegeSeparation sandbox/' ${SSHD_CONFIG}

	info "Enforce Restriction of user environnement"
	sed -i 's/.*PermitUserEnvironment.*/PermitUserEnvironment no/' ${SSHD_CONFIG}

	info "Restrict number of active sessions = Max is 3 sessions"
	sed -i 's/.*MaxSessions.*/MaxSessions 3/' ${SSHD_CONFIG}

	info "Lower Grace Time number minimize the risk of brute force attacks"
	sed -i 's/.*LoginGraceTime.*/MaxSessions 60/' ${SSHD_CONFIG}

	info "Deny ROOT account usage"
	sed -i "s/^.*PermitRootLogin.*$/PermitRootLogin no/g" ${SSHD_CONFIG}

	info "Deny password authentication method"
	sed -i 's/.*PubkeyAuthentication.*/PubkeyAuthentication yes/g' ${SSHD_CONFIG}
	sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication no/g' ${SSHD_CONFIG}
	sed -i 's/.*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/g' ${SSHD_CONFIG}
	sed -i 's/.*UsePAM.*/UsePAM no/g' ${SSHD_CONFIG}

	info "Restrict to ECDSA or RSA server keypair usage"
	rm -f $SSHD_DIR/ssh_host_dsa*
	rm -f $SSHD_DIR/ssh_host_ed*

	info "Enforce validation of file modes and ownership of the user before accepting login"
	sed -i 's/.*StrictModes.*/StrictModes yes/g' ${SSHD_CONFIG}

	info "Limit max authentication tries, even authentication is Pubkey limited"
	sed -i 's/.*MaxAuthTries.*/MaxAuthTries 3/g' ${SSHD_CONFIG}

	info "Prevent X11 Forwading - Graphical Interface Denial"
	sed -i 's/.*X11Forwarding.*/X11Forwarding no/g' ${SSHD_CONFIG}

	info "Prevent TCP Forwarding on server"
	sed -i 's/.*AllowTcpForwarding.*/AllowTcpForwarding no/g' ${SSHD_CONFIG}

	warn "Restrict allowed crypto algorithms"
    printf "Ciphers aes256-ctr\n" >> ${SSHD_CONFIG}
	printf "MACs hmac-sha2-512,hmac-sha2-256\n" >> ${SSHD_CONFIG}

	info "Enforcing enhanced logging of SSH Server activities"
	sed -i 's/.*PrintLastLog.*/PrintLastLog yes/g' ${SSHD_CONFIG}
	sed -i 's/.*SyslogFacility.*/SyslogFacility AUTH/g' ${SSHD_CONFIG}
	sed -i 's/.*LogLevel.*/LogLevel INFO/g' ${SSHD_CONFIG}

	info "Reload configuration of OpenSSH Server"
    systemctl restart ssh
	if [ $? != 0 ]; then
		error "FAILED TO APPLY SECURITY CONFIG\n\n"
        warn "Use this command for details : 'journalctl -u openssh-server.service -b'"
	else 
		info "SSHD Server is now SECURE"
		info "See ya space cowboy !"
	fi
}

### MAIN SCRIPT
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


if [[ $USAGE = 1 ]]; then
	usage
	exit 0
elif [[ $VERSION = 1 ]]; then
	show_version
	exit 0
elif [[ $HARDEN_SSHD = 1 ]]; then
    check_root
	check_sshd
	harden_sshd
	exit 0
else 
	error "Invalid argument. See help for more details.\n"
	exit 128
fi

### EOF ###
