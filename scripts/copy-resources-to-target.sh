#!/bin/bash

readonly LOG_FILE="/target/var/log/triveni-install.log"

mkdir -p /target/var/log
exec > >(tee -a "$LOG_FILE") 2>&1
echo "**********************************************************************"
echo "Running copy-resources-to-target.sh (copying resources to /target/tmp/resources)"


# mkdir -p /target/tmp/resources
# mkdir -p /target/tmp/resources/os-extras
mkdir -p /target/var/triveni/install
cp -Ra /cdrom/pool/install/* /target/var/triveni/install

# if [ -f /cdrom/pool/install/ssxm_*.deb ]; then
#     mkdir -p /target/var/triveni/iso
#     cp /cdrom/pool/install/ssxm_*.deb /target/var/triveni/iso
# fi

# if [ -f /cdrom/pool/streamscope-mt/*.deb ]; then
#     mkdir -p /target/var/triveni/iso
#     cp /cdrom/pool/streamscope-mt/*.deb /target/var/triveni/iso
# fi

# Create these directories so install_repo.sh can detect/install XM and MT if their debs are present
# if [ -f /cdrom/pool/repo/ssxm_*.deb ]; then
#     mkdir -p /target/opt/ssxm
# fi

# if [ -f /cdrom/pool/repo/ssmt_*.deb ]; then
#     mkdir -p /target/opt/ssmt
# fi

# cp -Ra /cdrom/pool/repo/* /target/var/triveni/iso || true
# chmod +x /target/var/triveni/iso/*.sh
# chmod +x /target/var/triveni/iso/scripts/*.sh

chmod +x /target/var/triveni/install/*.sh

cp -Ra /cdrom/pool/os-extras /target/tmp
# cp /cdrom/scripts/revert-kernel.sh /target/tmp/resources
# cp /cdrom/scripts/install-extras-debs.sh /target/tmp/resources
# cp /cdrom/scripts/create-systemd-links.sh /target/tmp/resources
# cp /cdrom/scripts/in-target-late-command.sh /target/tmp/resources
# cp /cdrom/scripts/rename-ifaces.sh /target/tmp/resources
chmod +x /target/tmp/resources/*.sh

exit 0
