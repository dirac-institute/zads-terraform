#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker containers whenever the
# hosts starts.
#

set -xe

#
# prepare the kafka data (log) volume
#

if file -sLb /dev/sda | grep filesystem; then
	echo "Filesystem already exists on /dev/sda; preserving"
else
	mkfs.ext4 -F /dev/sda
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

PRIVATE_IP=$(ifconfig eth1 | grep "inet " | awk '{print $2}')
PUBLIC_IP=$(ifconfig eth0 | grep "inet " | awk '{print $2}')
HOSTNAME=$(hostname -s)
REPLICA=${HOSTNAME#kafka}
PUBLIC_HOSTNAME=$(hostname -s)
PRIVATE_HOSTNAME="zk${REPLICA}.ztf.mjuric.org"

# Make sure that zookeeper binds to the private IP only
sed "s/\$PRIVATE_IP/$PRIVATE_IP/" config/zookeeper.properties > /etc/kafka/zookeeper.properties
# Store this replica number
echo "$REPLICA" > /var/lib/zookeeper/myid

# Kafka setup
sed "s/\$REPLICA/$REPLICA/; s/\$PUBLIC_HOSTNAME/$PUBLIC_HOSTNAME/; s/\$PRIVATE_HOSTNAME/$PRIVATE_HOSTNAME/;" config/server.properties > /etc/kafka/server.properties

#
# Set up systemd services that will start mirrormaker and kafka
#
mkdir /etc/ztf
cp config/{ipac,uw}.properties /etc/ztf
cp config/ztf-mirrormaker.service /etc/systemd/system/

systemctl daemon-reload

#
# Enable and start it all up
#
exit

systemctl start confluent-zookeeper
systemctl enable confluent-zookeeper

systemctl start confluent-kafka
systemctl enable confluent-kafka

systemctl start ztf-mirrormaker
systemctl enable ztf-mirrormaker
