#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker containers whenever the
# hosts starts.
#

#
# set up firewall and enable it
#
yum -y install firewalld
systemctl start firewalld
systemctl enable firewalld

cp config/kafka.xml /etc/firewalld/services/
cp config/ztf-trusted.xml /etc/firewalld/zones/

firewall-cmd --zone=public --change-interface=eth0 --permanent
systemctl reload firewalld

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
yum install confluent-kafka-2.11

cp config/zookeeper.properties /etc/kafka
cp config/server.properties /etc/kafka

systemctl start confluent-zookeeper
systemctl enable confluent-zookeeper

systemctl start confluent-kafka
systemctl enable confluent-kafka


#
# Set up systemd services that will start mirrormaker and kafka
#
mkdir /etc/ztf
cp config/{ipac,uw}.properties /etc/ztf
cp config/ztf-mirrormaker.service /etc/systemd/system/

systemctl daemon-reload
systemctl start ztf-mirrormaker
systemctl enable ztf-mirrormaker
