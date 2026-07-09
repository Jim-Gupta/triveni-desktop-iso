#!/bin/bash

readonly LOG_FILE="/target/var/log/triveni-install.log"

mkdir -p /target/var/log
exec > >(tee -a "$LOG_FILE") 2>&1
echo "**********************************************************************"
echo "Running copy-resources-to-target.sh (copying resources to /target/tmp/resources)"

mkdir -p /target/var/triveni/install
cp -Ra /cdrom/pool/install/* /target/var/triveni/install

chmod +x /target/var/triveni/install/*.sh

mkdir -p /target/tmp/resources
cp -Ra /cdrom/pool/os-extras/. /target/tmp/resources/
chmod +x /target/tmp/resources/*.sh

exit 0
