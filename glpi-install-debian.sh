#!/bin/bash
#@file

# GLPI Installation script for debian-like distros
#
# NOTE ! This script expects to be running as under ROOT ID
#

## User Informaiton Display functions
function error() { echo -e "['\e[31m'ERROR'\e[0m'] $1"; }
function warn()  { echo -e "['\e[33m'WARNING'\e[0m'] $1"; }
function info()  { echo -e "['\e[32m'INFO'\e[0m'] $1"; }

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
    IPADRESS=$(ip addr show $INTERFACE | grep inet | awk '{ print $2; }' | sed 's/\/.*$//' | head -n 1)
    HOST=$(hostname)
}

function install_packages()
{
    info "Installing packages..."
    apt update &>/dev/null
    apt install --yes --no-install-recommends \
        apache2 \
        libapache2-mod-php \
        mariadb-server \
        perl \
        curl \
        jq \
        php \
        apcupsd &>/dev/null

    info "Installing php extensions..."
    apt install --yes --no-install-recommends \
        php-ldap \
        php-imap \
        php-apcu \
        php-xmlrpc \
        php-cas \
        php-mysqli \
        php-mbstring \
        php-curl \
        php-gd \
        php-simplexml \
        php-xml \
        php-intl \
        php-zip \
        php-bz2 &>/dev/null

    info "Activating & Restarting MariaDB and Apache2..."
    systemctl enable mariadb
    systemctl enable apache2
    systemctl restart mariadb
    systemctl restart apache2
    if [[ $(systemctl is-active mariadb) != "active" || $(systemctl is-active apache2) != "active" ]]; then
        error "MariaDB or Apache2 services is INACTIVE !";
        warn "Use this command for details : 'journalctl -u <service-name>.service -b'"
        exit $?
    else
        info "MariaDB and Apache2 services are ACTIVE !"
    fi
}

function mariadb_configure()
{
    ## Do custom hardening due to 'mysql_secure_installation' bugs

    info "Configuring and hardening MariaDB..."
    SLQROOTPWD=$(openssl rand -base64 48 | cut -c1-16 )
    SQLGLPIPWD=$(openssl rand -base64 48 | cut -c1-16 )

    # Set the root password
    mysql -e "UPDATE mysql.user SET Password = PASSWORD('$SLQROOTPWD') WHERE User = 'root'"
    # Remove anonymous user accounts
    mysql -e "DELETE FROM mysql.user WHERE User = ''"
    # Disable remote root login
    mysql -e "DELETE FROM mysql.user WHERE User = 'root' AND Host NOT IN ('localhost', '127.0.0.1', '::1')"
    # Remove the test database
    mysql -e "DROP DATABASE test"

    # Reload privileges
    mysql -e "FLUSH PRIVILEGES"

    # Create database for GLPI
    # Create default user for GLPI with privileges
    mysql -u root -p'$SLQROOTPWD' <<EOF
CREATE DATABASE glpidb;
CREATE USER 'glpi_user'@'localhost' IDENTIFIED BY '$SQLGLPIPWD';
GRANT ALL PRIVILEGES ON glpidb.* TO 'glpi_user'@'localhost';
FLUSH PRIVILEGES;
QUIT;
EOF

}

function glpi_install()
{
    info "Downloading and installing the latest version of GLPI..."
    GLPI_DL_LINK=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/latest | jq -r '.assets[0].browser_download_url')
    wget -O /tmp/glpi-latest.tgz $GLPI_DL_LINK
    if [ $? -ne 0 ]; then
        error "Failed to download GLPI Source Code  Exiting ..."
        exit $?
    fi
    tar xzf /tmp/glpi-latest.tgz -C /var/www/html/
    chown -R www-data:www-data /var/www/html/glpi
    chmod -R 775 /var/www/html/glpi

    info "Setting up Virtual Host on Apache2"
    cat > /etc/apache2/sites-available/000-default.conf << EOF
<VirtualHost *:80>
        DocumentRoot /var/www/html/glpi

        <Directory /var/www/html/glpi>
                AllowOverride All
                Order Allow,Deny
                Allow from all
        </Directory>

        ErrorLog /var/log/apache2/error-glpi.log
        LogLevel warn
        CustomLog /var/log/apache2/access-glpi.log combined
</VirtualHost>
EOF

    echo "ServerSignature Off" >> /etc/apache2/apache2.conf
    echo "ServerTokens Prod" >> /etc/apache2/apache2.conf

    # Setup CRON Task 
    echo "*/2 * * * * www-data /usr/bin/php /var/www/html/glpi/front/cron.php &>/dev/null" >> /etc/cron.d/glpi

    info "Starting GLPI Web Server ..."
    a2enmod rewrite && service apache2 restart

    if [[ $(systemctl is-active apache2) != "active" ]]; then
        error "Apache2 service is INACTIVE !";
        warn "Use this command for details : 'journalctl -u <service-name>.service -b'"
        exit $?
    else
        info "Apache2 service is UPDATED & ACTIVE !"
    fi
}

function setup_db()
{
    info "GLPI - Setting up database ..."
    cd /var/www/html/glpi
    php bin/console db:install --db-name=glpidb --db-user=glpi_user --db-password=$SQLGLPIPWD --no-interaction
    if [ $? -ne 0 ]; then
        error "Failed to update GLPI Database in PHP Module. Exiting ... "
        exit $?
    fi
    rm -rf /var/www/html/glpi/install
    info "GLPI - Database updated"
}

function install_summary()
{
    info "=======> GLPI installation details  <======="
    info "==> GLPI"
    info "Default user accounts are:"
    info "USER       -  PASSWORD       -  ACCESS"
    info "glpi       -  glpi           -  admin account,"
    info "tech       -  tech           -  technical account,"
    info "normal     -  normal         -  normal account,"
    info "post-only  -  postonly       -  post-only account."
    echo ""
    info "==> MariaDB"
    info "root password:           $SLQROOTPWD"
    info "glpi_user password:      $SQLGLPIPWD"
    info "GLPI database name:      glpidb"
    echo ""
    info "Finalize setup connecting to GLPI"
    info "http://$IPADRESS/glpi or http://$HOST/glpi" 
    echo ""
    info "<==========================================>"
    echo ""
}

##
## MAIN SCRIPT EXECUTION

check_root
check_distro
net_info
install_packages
mariadb_configure
glpi_install
setup_db

## TODO - Add phpmyadmin for ease of use

install_summary

##### EOF #####
