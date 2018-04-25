#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker containers whenever the
# hosts starts.
#

set -xe

#
# Utils to make configuration easier
#

# Copy a file, while expanding certain variables
# cp_with_subst <source> <dest> [variables]
cp_with_subst()
{
	cp "$1" "$2"
	_DEST="$2"
	shift 2
	for VAR in "$@"; do
		sed -i "s|\$$VAR|${!VAR}|" "$_DEST"
	done
}

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
# Add swap space, just in case
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

#
# ZOOKEEPER
#
cp config/zookeeper.properties /etc/kafka/zookeeper.properties

#
# KAFKA
#
cp config/server.properties /etc/kafka/server.properties
for BROKER in 0 1 2; do
	((PORT = 9092 + BROKER))
	LISTENERS="PLAINTEXT://:$PORT"
	cp_with_subst config/ztf-kafka-template.service /etc/systemd/system/ztf-kafka-$BROKER.service BROKER LISTENERS
done

#
# MIRROR-MAKER
#
mkdir /etc/ztf
cp config/{ipac,uw}.properties /etc/ztf
cp config/ztf-mirrormaker.service /etc/systemd/system/

systemctl daemon-reload

#
# Install useful utilities
#
yum install -y gcc patch ruby-devel
gem install kafkat
cp config/dot-kafkat.cfg ~/.kafkatcfg

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
