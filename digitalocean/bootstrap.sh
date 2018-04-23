#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker containers whenever the
# hosts starts.
#

set -xe

#
# Utils to make configuration easier
#
PRIVATE_IP=$(ifconfig eth1 | grep "inet " | awk '{print $2}')
PUBLIC_IP=$(ifconfig eth0 | grep "inet " | awk '{print $2}')
HOSTNAME=$(hostname -s)
REPLICA=${HOSTNAME#kafka}
PUBLIC_HOSTNAME=$(hostname)
PRIVATE_HOSTNAME="zk${REPLICA}.ztf.mjuric.org"

# Copy a file, while expanding certain variables
# cp_with_subst <source> <dest>
cp_with_subst()
{
	cp "$1" "$2"
	for VAR in PRIVATE_IP PUBLIC_IP HOSTNAME REPLICA PUBLIC_HOSTNAME PRIVATE_HOSTNAME; do
		sed -i "s/\$$VAR/${!VAR}/" "$2"
	done
}

#
# prepare and mount the kafka data (log) partition
#

if file -sLb /dev/sda | grep filesystem; then
	echo "Filesystem already exists on /dev/sda; preserving"
else
	mkfs.ext4 -m 0 -F /dev/sda
fi

mkdir -p /kafka-data
echo "/dev/sda /kafka-data ext4 defaults,nofail,discard 0 0" >> /etc/fstab
mount /kafka-data

#
# set up firewall and enable it
#
yum -y install firewalld

cp config/kafka.xml /etc/firewalld/services/
cp config/ztf-trusted.xml /etc/firewalld/zones/
firewall-offline-cmd --zone=public --change-interface=eth0
firewall-offline-cmd --zone=trusted --change-interface=eth1

systemctl start firewalld
systemctl enable firewalld

#
# Add swap space. mirrormaker runs out of memory otherwise.
#
dd if=/dev/zero of=/swapfile count=16 bs=512MiB
chmod 600 /swapfile
mkswap /swapfile
echo "/swapfile   swap    swap    sw  0   0" >> /etc/fstab
swapon -a

#
# Install and configure kafka, zookeeper, and mirrormaker
#
rpm --import https://packages.confluent.io/rpm/4.1/archive.key
cp config/confluent.repo /etc/yum.repos.d
yum install -y java
yum install -y confluent-kafka-2.11

# Configure zookeeper
cp_with_subst config/zookeeper.properties /etc/kafka/zookeeper.properties
echo "$REPLICA" > /var/lib/zookeeper/myid

# Configure kafka
if ! -d /kafka-data/kafka; then
	mv /var/lib/kafka /kafka-data
else
	# Retain existing data
	rmdir /var/lib/kafka
fi
ln -sf /kafka-data/kafka /var/lib/
cp_with_subst config/server.properties /etc/kafka/server.properties
cp config/ztf-kafka.service /etc/systemd/system/

# Configure mirror-maker
mkdir /etc/ztf
cp config/{ipac,uw}.properties /etc/ztf
cp config/ztf-mirrormaker.service /etc/systemd/system/

systemctl daemon-reload

# Install useful utilities
yum install -y gcc patch ruby-devel
gem install kafkat
cp config/dot-kafkat.cfg ~/.kafkat.cfg

#
# Enable and start it all up
#
exit

systemctl start confluent-zookeeper
systemctl enable confluent-zookeeper

systemctl start ztf-kafka
systemctl enable ztf-kafka

systemctl start ztf-mirrormaker
systemctl enable ztf-mirrormaker
