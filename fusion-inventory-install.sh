#!/bin/bash
#@file

# FUSION INVENTORY Installation script for debian-like distros
# Prerequisites = GLPI is installed and active
# NOTE ! This script expects to be running as under ROOT ID
#

## User Informaiton Display functions
INSTALL_LOG="/var/log/install-glpi.log"
function error() { echo -e "[\e[31m  ERROR  \e[0m] - $(date --rfc-3339=seconds) - $1" | tee ${INSTALL_LOG}; }
function warn()  { echo -e "[\e[33m WARNING \e[0m] - $(date --rfc-3339=seconds) - $1" | tee ${INSTALL_LOG}; }
function info()  { echo -e "[\e[32m  INFOS  \e[0m] - $(date --rfc-3339=seconds) - $1" | tee ${INSTALL_LOG}; }


function check_root()
{
    if [[ "$(id -u)" -ne 0 ]] ; then
        warn "This script must be run as root" >&2
        exit 1
    else
        info "Root privileges validated"
    fi
}

function check_distro()
{
    DEBIAN_VERSIONS=("11")
    UBUNTU_VERSIONS=("22.04")

    DISTRO=$(lsb_release -is)
    VERSION=$(lsb_release -rs)

    if [ "$DISTRO" == "Debian" ]; then
        if [[ " ${DEBIAN_VERSIONS[*]} " == *" $VERSION "* ]]; then
                info "Operating system version ($DISTRO $VERSION) = COMPLIANT."
        else
            error "Operating system version ($DISTRO $VERSION) = NOT COMPLIANT"
            error "Exiting..."
            exit 1
        fi

    elif [ "$DISTRO" == "Ubuntu" ]; then
        if [[ " ${UBUNTU_VERSIONS[*]} " == *" $VERSION "* ]]; then
            info "Operating system version ($DISTRO $VERSION) = COMPLIANT."
            # Since Ubuntu 22.04 we need to change 'needrestart' to automatic and no more interactive
            sed -i "s/^#\$nrconf{restart}.*/\$nrconf{restart} = 'a';/g" /etc/needrestart/needrestart.conf
        else
            error "Operating system version ($DISTRO $VERSION) = NOT COMPLIANT"
            error "Exiting..."
            exit 1
        fi

    else
            error "Operating system version ($DISTRO $VERSION) = NOT COMPLIANT"
            error "Exiting..."
            exit 1
    fi
}

function net_info()
{
    INTERFACE=$(ip route | awk 'NR==1 {print $5}')
    IPADDR=$(ip addr show $INTERFACE | grep inet | awk '{ print $2; }' | sed 's/\/.*$//' | head -n 1)
    HOST=$(hostname)
}

function install_packages()
{
    info "Installing packages..."
    apt update &>/dev/null
    wget https://github.com/fusioninventory/fusioninventory-for-glpi/archive/glpi9.3+1.3.tar.gz
    if [ $? -ne 0 ]; then
        error "Failed to download Fusion Inventory Source Code. Exiting ..."
        exit $?
    fi
    tar -zxf glpi9.3+1.3.tar.gz -C /var/www/html/glpi/plugins
    rm -fr glpi9.3+1.3.tar.gz
    chown -R www-data /var/www/html/glpi/plugins
    cd /var/www/html/glpi/plugins
    mv fusioninventory-for-glpi-glpi9.3-1.3/ fusioninventory/
}


function install_summary()
{
    info "=======> Fusion Inventory Plugin  <======="
    echo ""
    info "Finalize plugin setup from GLPI web interface"
    info "http://$IPADDR/ or http://$HOST/" 
    echo ""
    info " - Connect with glpi super admin account"
    info " - Go to 'Configuration > Plugins' menu item"
    info " - Check 'Fusion Inventory' is available in plugins list "
    info " - If needed click on 'Install' to setup the plugin"
    info " - Click on 'Activate' to deploy the plugin in GLPI Web Interface"
    echo ""
    info "Configure Fusion Inventory Plugin following these steps"
    info " - Install & Configure FusionInventory Agents"
    info " - Setup at least one agent form MS Windows Server and one Linux Server"
    echo ""
    warn "More informations here : https://documentation.fusioninventory.org/"
    info "<==========================================>"
    echo ""
}

##
## MAIN SCRIPT EXECUTION

check_root
check_distro
net_info
install_packages
install_summary

##### EOF #####
