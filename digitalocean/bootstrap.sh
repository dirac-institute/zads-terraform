#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker containers whenever the
# hosts starts.
#

set -xe

#
# set up firewall and enable it
#
yum -y install firewalld
systemctl start firewalld
systemctl enable firewalld

cp config/kafka.xml /etc/firewalld/services/
cp config/ztf-trusted.xml /etc/firewalld/zones/

firewall-cmd --zone=public --change-interface=eth0 --permanent
firewall-cmd --zone=trusted --change-interface=eth1 --permanent
systemctl restart firewalld

#
# Add swap space. mirrormaker runs out of memory otherwise.
#
dd if=/dev/zero of=/swapfile count=16 bs=512MiB
chmod 600 /swapfile
mkswap /swapfile
echo "/swapfile   swap    swap    sw  0   0" >> /etc/fstab
swapon -a

#
# Install the application (kafka)
#
rpm --import https://packages.confluent.io/rpm/4.1/archive.key
cp config/confluent.repo /etc/yum.repos.d
yum install -y java
#yum install -y confluent-platform-oss-2.11
yum install -y confluent-kafka-2.11

## DO Droplet Metadata Service:https://www.digitalocean.com/community/tutorials/an-introduction-to-droplet-metadata
# PRIVATE_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/private/0/ipv4/address)
# PUBLIC_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
# HOSTNAME=$(curl -s http://169.254.169.254/metadata/v1/hostname)
## More generic, but sensitive to parsing
PRIVATE_IP=$(ifconfig eth1 | grep "inet " | awk '{print $2}')
PUBLIC_IP=$(ifconfig eth0 | grep "inet " | awk '{print $2}')
HOSTNAME=$(hostname)
REPLICA=${HOSTNAME#kafka}

sed "s/\$PRIVATE_IP/$PRIVATE_IP/" config/zookeeper.properties > /etc/kafka/zookeeper.properties
echo "$REPLICA" > /var/lib/zookeeper/myid

cp config/server.properties /etc/kafka

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

#systemctl start confluent-zookeeper
#systemctl enable confluent-zookeeper
#
#systemctl start confluent-kafka
#systemctl enable confluent-kafka
#
#systemctl start ztf-mirrormaker
#systemctl enable ztf-mirrormaker
