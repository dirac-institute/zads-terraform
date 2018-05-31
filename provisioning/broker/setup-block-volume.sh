#!/bin/bash

set -e

#
# Set up storage on the block volume (if given)
#
if [[ ! -b /dev/sda ]]; then
	echo "No /dev/sda; is the block volume attached"
fi

yum -y install lvm2

systemctl stop ztf-mirrormaker ztf-kafka ztf-zookeeper

# Activate the volume group, in case it was deactivated
# previously (you should deactivate it when removing the
# logical volume from a machine)
vgchange -ay zads-data

# chown these two to root to prevent accidental writing
# if the block volume isn't mounted
chown root.root /var/lib/{kafka,zookeeper}

#
# set up mounts for /var/lib/kafka and /var/lib/zookeeper
#
mkdir -p /zads-data
echo "LABEL=zads-data                           /zads-data              ext4    defaults,discard 0 0" | tee -a /etc/fstab
echo "/zads-data/var/lib/kafka                  /var/lib/kafka          none    bind             0 0" | tee -a /etc/fstab
echo "/zads-data/var/lib/zookeeper              /var/lib/zookeeper      none    bind             0 0" | tee -a /etc/fstab
mount -a

echo "Done. Verify everything looks fine and restart the services:"
echo "   systemctl start ztf-mirrormaker ztf-kafka ztf-zookeeper"

### To empty the directories:
## rm -r /zads-data/var/lib/{kafka,zookeeper}/*