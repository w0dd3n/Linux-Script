#!/bin/bash

# PARAMETER TO BE UPDATED
IP_ADDR="192.168.1.122"
FQDN="wp-02.example.com"
APACHE_LOG_DIR="/var/log/apache2"

#
# Do we run under ROOT ID
#
if [ "$(id -u)" != "0" ]; then
	echo "This script must be run as root" 1>&2
	exit 1
fi

## CHANGE NETWORK CONFIG
cat <<EOF>/home/simplon/netplan.conf
network:
  version: 2
  renderer: networkd
  ethernets:
    ens18:
      addresses:
        - $IP_ADDR/24
      nameservers:
        addresses: [192.168.1.254, 8.8.8.8]
      routes:
        - to: default
          via: 192.168.1.1
EOF

cp /home/simplon/netplan.conf /etc/netplan/00-installer-config.yaml
netplan apply 

## CHANGE WORDPRESS DIRECTORY FOR NEW FQDN
mv /var/www/example.com /var/www/$FQDN
chown -R www-data:www-data /var/www/$FQDN
find /var/www/$FQDN/ -type d -exec chmod 750 {} \;
find /var/www/$FQDN/ -type f -exec chmod 640 {} \;

## CHANGE DOMAIN DIRECTORY FOR APACHE2
rm /etc/apache2/sites-available/example.com.conf
touch /etc/apache2/sites-available/$FQDN.conf
cat <<EOF>/home/simplon/$FQDN.conf
<VirtualHost *:80>
    ServerName $FQDN
    ServerAlias www.$FQDN 
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/$FQDN
    ErrorLog $APACHE_LOG_DIR/error.log
    CustomLog $APACHE_LOG_DIR/access.log combined
    <Directory /var/www/$FQDN/>
      AllowOverride All
    </Directory>
</VirtualHost>
EOF
cp /home/simplon/$FQDN.conf /etc/apache2/sites-available/$FQDN.conf
a2enmod rewrite
a2ensite $FQDN
a2dissite 000-default
a2dissite default-ssl
apache2ctl configtest
systemctl restart apache2

## SETUP WORDPRESS CONFIGURATION FILE
cat <<EOF>/home/simplon/config.awk
NR==FNR {
    insert = (NR==1 ? "" : insert ORS) $0
    next
}
sub(/^## BEGIN.*/,"") {
  beg = $0 "## BEGIN\n"
  inSub = 1
}
inSub {
  if ( sub(/.*^## END/,"") ) {
    end = "\n## END" $0
    print beg insert end
    inSub = 0
  }
  next
}
{ print }
EOF

curl -s https://api.wordpress.org/secret-key/1.1/salt/ > /home/simplon/wp-api.txt
echo "## SECRET KEY RELEASE $(date --rfc-3339='seconds')" >> /home/simplon/wp-api.txt
cp /var/www/apache2/wp-config.php /var/www/apache2/wp-config.php.old
awk -f /home/simplon/config.awk /home/simplon/wp-api.txt /var/www/apache2/wp-config.php.old > /var/www/apache2/wp-config.php
rm /home/simplon/config.awk
rm /home/simplon/wp-api.txt