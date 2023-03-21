#!/bin/bash

###
# TITRE  = Docker Engine Installation on Ubuntu
# AUTHOR = Obejero, Cedric - <cedric.obejero@tanooki.fr>
# DATE   = Oct. 20th, 2022
# 
###

BASENAME=$(basename $0)
AUTHOR="Cedric OBEJERO <cedric.obejero@tanooki.fr>"
RELEASE="V1R0"
REL_DATE="Oct. 20th, 2022"

RST='\033[0;0m'
BOLD='\033[1;37m'
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[0;33m'
BLUE='\033[0;34m'

CLEAR_CONFIG=0
INSTALL_DEFAULT=1
PORTAINER=0
USAGE=0
VERSION=0

RC_ERR=0

while [[ $# > 0 ]]; do
	ARG="$1"
	case $ARG in
	-c|--clear-config)
		CLEAR_CONFIG=1
		;;
	-p|--portainer)
		PORTAINER=1
		;;
	-h|--help)
		USAGE=1
		;;
	-v|--version)
		VERSION=1
		;;
	*)
		printf "[${RED}ERROR${RST}] - Unknonw argument, aborting\n\n"
		exit 128
		;;
	esac
	shift
done

usage() {
	printf "${BOLD}NAME${RST}\n"
	printf "	$BASENAME\n\n"
	printf "${BOLD}SYNOPSIS${RST}\n"
	printf "	$BASENAME [OPTIONS]\n\n"
	printf "${BOLD}DESCRIPTION${RST}\n"
	printf "	DOCKER ENGINE Installation Script for UBUNTU distro\n"
	printf "	Following Docker Guide Lines - https://docs.docker.com/engine/install/ubuntu/\n\n"
	printf "	Available options are as follow.\n\n"
	printf "	-c, --clear-config\n"
	printf "		Script will automatically remove previous installation of components\n"
	printf "		This option will enforce to purge existing configuration files\n\n"
	printf "        -p, --portainer\n"
	printf "                Install and start management server within a container,\n"
	printf "                Portainer.io allow to deploy, configure, troubleshoot and secure containers.\n"
	printf "	        Solution is compliant with K8s, Docker, Swarm and Nomad.\n\n"
	printf " 	-h, --help\n"
	printf "		Display current help information\n\n"
	printf "	-v, --version\n"
	printf " 		Display command release informations\n\n"
}

show_version() {
	printf "${BLUE}NAME${RST}    $BASENAME\n"
	printf "${BLUE}AUTHOR${RST}  $AUTHOR\n"
	printf "${BLUE}RELEASE${RST} $RELEASE\n"
	printf "${BLUE}DATE${RST}    $REL_DATE\n\n"
}

install_docker() {
	if [ "$(id -u)" != "0" ]; then
		printf "[${RED}ERROR${RST}] - Privileged access required - see 'sudo' for more information\n"
		exit 126
	fi
	
	printf "[${GRN}INFO${RST}] - Uninstall old versions\n"
	if [[ $CLEAR_CONFIG = 1 ]]; then
		UninstallOpt="purge"
	else
		UninstallOpt="autoremove"
	fi
	pkgList="docker docker-engine docker.io containerd runc"
	pkgToUninstall=""
	for isValidPkg in $(echo $pkgList); do
		$(dpkg --status $isValidPkg &>/dev/null)
		if [[ $? -eq 0 ]]; then 
			pkgToUninstall="$pkgToUninstall $isValidPkg"
		fi
	done
	if [ ! -z $pkgToUninstall ]; then
		apt $UninstallOpt $pkgToUninstall &>/dev/null
		if [ $? -eq 0 ]; then
			printf "[${GRN}INFO${RST}] - Old versions uninstall - DONE\n"
		else
			printf "[${RED}ERROR${RST}] - Old versions uninstallation FAILED - Error: $?\n"
			exit $?
		fi
	else
		printf "[${GRN}INFO${RST}] - No package to remove - DONE\n"
	fi

	printf "[${GRN}INFO${RST}] - Set up the installation repository\n"
	apt update &>/dev/null
	apt install -y ca-certificates curl gnupg lsb-release 
	if [ ! $? -eq 0 ]; then
		printf "[${RED}ERROR${RST}] - Repository set up tools installation FAILED - Error: $?\n"
		exit $?
	fi
	mkdir -p /etc/apt/keyrings
	eval "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
	if [ ! $? -eq 0 ]; then
	        printf "[${RED}ERROR${RST}] - Repository keyring set up FAILED - Error: $?\n"
	        exit $?
	fi
	source_list="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
	eval "echo ${source_list} | tee /etc/apt/sources.list.d/docker.list &>/dev/null"
	if [ ! $? -eq 0 ]; then
		printf "[${RED}ERROR${RST}] - Repository final set up FAILED - Error: $?\n"
                exit $?
        fi
	printf "[${GRN}INFO${RST}] - Repository set up - DONE\n"

	printf "[${GRN}INFO${RST}] - Download and Install DOCKER PACKAGES\n"
	apt update &>/dev/null
	apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
	if [ ! $? -eq 0 ]; then
		printf "[${RED}ERROR${RST}] - Repository set up tools installation FAILED - Error: $?\n"
		exit $?
	fi
	printf "[${GRN}INFO${RST}] - Docker Packages Installation - DONE\n"


	printf "[${GRN}INFO${RST}] - Testing Docker Set up ...\n"
	docker run hello-world &>/dev/null
	if [ ! $? -eq 0 ]; then
		printf "[${RED}ERROR${RST}] - Docker Test FAILED - Error: $?\n"
		exit $?
	fi
	printf "[${GRN}INFO${RST}] - Docker is up and running - DONE\n"

}

install_portainer() {
	printf "[${GRN}INFO${RST}] - Portainer Installation TO BE IMPLEMENTED ;)\n"
}

if [[ $USAGE = 1 ]]; then
	usage
elif [[ $VERSION = 1 ]]; then
	show_version
elif [[ $INSTALL_DEFAULT = 1 ]]; then
	install_docker
	if [[ $PORTAINER = 1 ]]; then
		install_portainer
	fi
else 
	printf "[${RED}ERROR${RST}] - Invalid operation requested\n"
	usage
	RC_ERR=128
fi

printf "[${GRN}INFO${RST}] - End of process\n\n"

exit $RC_ERR

### EOF ###
