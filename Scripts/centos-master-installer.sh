#!/bin/bash

mkdir ~/feathur-install/
touch ~/feathur-install/install.log
exec 3>&1 > ~/feathur-install/install.log 2>&1

function status {
	echo $1;
	echo $1 >&3
}

function check_installs {
	if ! type -p $1 > /dev/null; then
		status "Unfortunately $1 failed to install. Feathur install aborting."
		exit 1
	fi
}

function check_sanity {
	# Do some sanity checking.
	if [ $(/usr/bin/id -u) != "0" ]
	then
		status "Feathur must be installed as root. Please log in as root and try again."
		die 'Feathur must be installed as root. Please log in as root and try again.'
	fi

	if [ ! -f /etc/centos-release ]
	then
		status "Feathur must be installed on CentOS 6."
		die "Feathur must be installed on CentOS 6."
	fi

	if [ ! 6 == $(awk '{print $3}' /etc/centos-release | awk -F. '{print $1}') ]
	then
		status "Feathur must be installed on CentOS 6."
		die "Feathur must be installed on CentOS 6."
	fi
}

function die {
	echo "ERROR: $1" > /dev/null 1>&2
	exit 1
}

check_sanity


status "====================================="
status "     Welcome to Feathur Installation"
status "====================================="
status " "
status "Feathur master server installation."
status " "
status "Feathur will remove any existing apache,"
status "nginx, mysql or php services you have"
status "installed upon this server. It will"
status "also delete all custom config files"
status "that you may have."
status " "
status "It is recommended that you run this"
status "installer in a screen."
status " "
status "This script will begin installing"
status "Feathur in 10 seconds. If you wish to"
status "cancel the install press CTRL + C"
sleep 10
status "Feathur needs a bit of information before"
status "beginning the installation."
status " "
status "What hostname would you like to use (Example: manage.yourdomain.com):"
read user_host
status " "
status "What email would you like to use for your administrative account?"
read user_email

status " "
status "Removing excess programs..."
service httpd stop
yum -y remove httpd mysql* php* nginx lighttpd php-fpm vsftpd proftpd exim qmail postfix sendmail git pdns*

status "Installing essential programs..."
echo '[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/6/$basearch/
gpgcheck=0
enabled=1' > /etc/yum.repos.d/nginx.repo
status "Install: 1 of 3"

yum -y install http://download.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
yum -y update
yum -y install php php-fpm nginx mysql-server vim openssl php-mysql zip unzip pdns pdns-backend-mysql php-mcrypt rsync wget gcc make gcc-c++ zlib-devel perl-ExtUtils-Embed gettext curl-devel
status "Install: 2 of 3"

cd ~/feathur-install/
wget http://git-core.googlecode.com/files/git-1.8.1.1.tar.gz
tar -zxvf git-1.8.1.1.tar.gz
cd git-1.8.1.1
./configure
make
make install
ln -s /root/git-1.8.1.1/git /usr/bin/
status "Install: 3 of 3"

service mysqld stop
service php-fpm stop

status " "
status "Installing and configuring Feathur..."
cd ~
git clone -b develop https://github.com/BlueVM/Feathur.git /var/feathur
mkdir -p /var/feathur/data/{templates/{openvz,kvm},keys}
touch /var/feathur/data/log.txt
mkdir /home/root/
status "Configuring: 1 of 4"

cd ~/feathur-install/
ssh-keygen -t rsa -N "" -f ~/feathur-install/id_rsa
mkdir ~/.ssh/
cat id_rsa.pub >> ~/.ssh/authorized_keys
cp id_rsa /var/feathur/data/
cd /var/feathur/
chown -R nginx *
chmod -R 700 *
status "Configuring: 2 of 4"

mysqlpassword=$(< /dev/urandom tr -dc A-Z-a-z-0-9 | head -c${1:-32};)

cp /var/feathur/data/config.example /var/feathur/data/config.json
sed -i 's/databaseusernamehere/root/g' /var/feathur/data/config.json
sed -i 's/databasepasswordhere/'${mysqlpassword}'/g' /var/feathur/data/config.json
sed -i 's/databasenamehere/panel/g' /var/feathur/data/config.json
sed -i 's/randomlygeneratedsalthere/'${salt}'/g' /var/feathur/data/config.json
sed -i 's/hostnameforinstallhere/'${user_host}'/g' /var/feathur/data/config.json

/etc/init.d/mysqld start
salt=$(< /dev/urandom tr -dc A-Z-a-z-0-9 | head -c${1:-32};)
mysqladmin -u root password $mysqlpassword

while ! mysql -u root -p$mysqlpassword  -e ";" ; do
       echo "Unfortunately mysql failed to install correctly. Feathur installation aborting (Error #2)".
done
mysql -u root --password="$mysqlpassword" --execute="CREATE DATABASE IF NOT EXISTS panel;CREATE DATABASE IF NOT EXISTS dns;DROP DATABASE test;"
sed -i 's/admin@company.com/'${user_email}'/g' /var/feathur/data.sql
mysql -u root --password="$mysqlpassword" panel < /var/feathur/data.sql

cd ~/feathur-install/
status "Configuring: 3 of 4"

mv /etc/php-fpm.d/www.conf /etc/php-fpm.d/www.old
cp /var/feathur/feathur/includes/configs/php.conf /etc/php-fpm.d/www.conf
mv /etc/php.d/apc.ini /etc/php.d/apc.old
cp /var/feathur/feathur/includes/configs/php.ini /etc/php.ini

mkdir /usr/ssl
cd /usr/ssl
openssl genrsa -out feathur.key 1024
openssl rsa -in feathur.key -out feathur.pem
openssl req -new -key feathur.pem -subj "/C=US/ST=Oregon/L=Portland/O=IT/CN=www.feathur.com" -out feathur.csr
openssl x509 -req -days 365 -in feathur.csr -signkey feathur.pem -out feathur.crt

rm -rf /etc/nginx/conf.d/*
cp /var/feathur/feathur/includes/configs/nginx.feathur.centos.conf /etc/nginx/conf.d/

mv /etc/powerdns/pdns.conf /etc/powerdns/pdns.old
cp /var/feathur/feathur/includes/configs/pdns.conf /etc/powerdns/pdns.conf
sed -i 's/databasenamehere/dns/g' /etc/powerdns/pdns.conf
sed -i 's/databasepasswordhere/'${mysqlpassword}'/g' /etc/powerdns/pdns.conf
sed -i 's/databaseusernamehere/root/g' /etc/powerdns/pdns.conf

service nginx restart
service pdns start
service php-fpm start
ipaddress=$(ifconfig  | grep 'inet addr:'| grep -v '127.0.0.1' | grep -v '127.0.0.2' | cut -d: -f2 | awk '{ print $1}');
(crontab -l 2>/dev/null; echo "* * * * * php /var/feathur/feathur/cron.php") | crontab -
status "Configuring: 4 of 4"
status " "
status "=========FEATHUR_INSTALL_COMPLETE========"
status "Mysql Root Password: $mysqlpassword"
status "You can now login at https://$ipaddress:2026"
status "Username: "${user_email}""
status "Password: password"
status "========================================="
status "It is recommended you download the"
status "log ~/feathur-install/feathur-install.log"
status "and then delete it from your system."