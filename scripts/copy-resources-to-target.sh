#!/bin/bash

readonly LOG_FILE="/target/var/log/triveni-install.log"

mkdir -p /target/var/log
exec > >(tee -a "$LOG_FILE") 2>&1
echo "**********************************************************************"
echo "Running copy-resources-to-target.sh (copying resources to /target/tmp/resources)"

mkdir -p /target/var/triveni/install
cp -Ra /cdrom/pool/install/* /target/var/triveni/install

chmod +x /target/var/triveni/install/*.sh

if [ -d /cdrom/pool/install/drivers ]; then
	mkdir -p /target/var/triveni/drivers
	cp -Ra /cdrom/pool/install/drivers/. /target/var/triveni/drivers/
	find /target/var/triveni/drivers -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} +
fi

mkdir -p /target/tmp/resources
cp -Ra /cdrom/pool/os-extras/. /target/tmp/resources/
find /target/tmp/resources -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} +

if [ -d /cdrom/scripts/first-boot ]; then
	echo "Staging first-boot payload into /target/var/triveni/install/first-boot"
	mkdir -p /target/var/triveni/install/first-boot
	cp -Ra /cdrom/scripts/first-boot/. /target/var/triveni/install/first-boot/
	find /target/var/triveni/install/first-boot -name "*.sh" -exec chmod +x {} +

	if [ -f /target/var/triveni/install/first-boot/first-boot.service ]; then
		mkdir -p /target/etc/systemd/system
		mkdir -p /target/etc/systemd/system/graphical.target.wants
		cp -a /target/var/triveni/install/first-boot/first-boot.service /target/etc/systemd/system/first-boot.service
		ln -sf /etc/systemd/system/first-boot.service /target/etc/systemd/system/graphical.target.wants/first-boot.service
	fi
fi

if [ -d /tmp/backup ]; then
	echo "Found /tmp/backup, copying to /target/var/triveni/install/backup"
	mkdir -p /target/var/triveni/install/backup
	cp -aR /tmp/backup/. /target/var/triveni/install/backup/
	ls -l /target/var/triveni/install/backup/
fi


exit 0
