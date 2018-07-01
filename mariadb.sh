#!/bin/bash

api-events_update() {
	conf_write status-api $1
	if [[ -a /opt/webinoly/lib/api-events ]]; then
		source /opt/webinoly/lib/api-events
		api-events_catch_status $1
	fi
}


conf_read() {
	local val=$(grep -w "^${1}:.*" /opt/webinoly/webinoly.conf | cut -f 2 -d ':')
	echo $val
}

conf_write() {
	mkdir -p /opt/webinoly
	[[ ! -a /opt/webinoly/webinoly.conf ]] && sudo touch /opt/webinoly/webinoly.conf
	#if requested VAR exists overwrite it, if not, create it.
	sed -i "/^${1}:/d" /opt/webinoly/webinoly.conf
	sh -c "echo -n '$1:$2\n' >> /opt/webinoly/webinoly.conf"
}

conf_delete() {
	sed -i "/^${1}:/d" /opt/webinoly/webinoly.conf
}



pre_install() {
	sudo apt-get -qq update
	if [[ $(conf_read pre-packs) != true ]]; then
		# Check for missing essential packages
		api-events_update i1
		sudo apt-get -y -qq install software-properties-common
		sudo apt-get -y -qq install python-software-properties
		sudo apt-get -y -qq install pwgen
		sudo apt-get -y -qq install unzip
		sudo apt-get -y -qq install zip
		conf_write pre-packs true
		api-events_update i2
	fi
}


mysql_install() {
	api-events_update im1
	[[ $(conf_read mysql-client) != "true" ]] && mysql_client_install
	
	pre_install
	# debconf-utils for unattended scripts
	#  debconf-get-selections | grep phpmyadmin   <<-- list conf variables
	sudo apt-get -y install debconf-utils
	
	# Generate mysql user passwords
	local AUTOGENPASS_ROOT=`pwgen -s -1`
	local AUTOGENPASS_ADMIN=`pwgen -s -1`
	local enc_pass_root=$( echo $AUTOGENPASS_ROOT | openssl enc -a -salt )
	local enc_pass_admin=$( echo $AUTOGENPASS_ADMIN | openssl enc -a -salt )
	conf_write mysql-root $enc_pass_root
	conf_write mysql-admin $enc_pass_admin
	
	# MariaDB Installation
	echo "mariadb-server-10.2 mysql-server/root_password password $AUTOGENPASS_ROOT" | debconf-set-selections
	echo "mariadb-server-10.2 mysql-server/root_password_again password $AUTOGENPASS_ROOT" | debconf-set-selections
	sudo apt-get -y install mariadb-server

	#Instead of mysql_secure_installation we do this: (same but manually, because not acept unattended)
	#ALTER USER 'root'@'localhost' IDENTIFIED BY '${AUTOGENPASS_ROOT}';   <<<--- For MySQL 5.7.6 and newer as well as MariaDB 10.1.20 and newer instead of UPDATE
	sudo mysql --user=root -p$AUTOGENPASS_ROOT <<_EOF_
UPDATE mysql.user SET authentication_string = PASSWORD('${AUTOGENPASS_ROOT}') WHERE User = 'root' AND Host = 'localhost';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE USER IF NOT EXISTS 'admin'@'localhost' IDENTIFIED BY '${AUTOGENPASS_ADMIN}';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
_EOF_

	conf_write mysql true
	echo "${gre}MySQL has been installed successfully! ${end}"
	api-events_update im4
}
