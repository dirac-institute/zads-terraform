#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker whenever the
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
		sed -i "s|\$$VAR|${!VAR}|g" "$_DEST"
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
# set up inernal hostnames
#
PUBLIC_IP=$(ifconfig eth0 | grep "inet " | awk '{print $2}')
PRIVATE_IP=$(ifconfig eth1 | grep "inet " | awk '{print $2}')
echo "# Shortcuts used in config files" >> /etc/hosts
echo "$PUBLIC_IP public" >> /etc/hosts
echo "$PRIVATE_IP private" >> /etc/hosts

#
# Add swap space, just in case
#
dd if=/dev/zero of=/swapfile count=16 bs=512MiB
chmod 600 /swapfile
mkswap /swapfile
echo "/swapfile   swap    swap    sw  0   0" >> /etc/fstab
swapon -a

#
# Set up the Prometheus JMX exporter, for exporting JVM (JMX) metrics to Prometheus
#

mkdir -p /opt/jmx_exporter
curl -L https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.3.0/jmx_prometheus_javaagent-0.3.0.jar -o /opt/jmx_exporter/jmx_prometheus_javaagent.jar
mkdir /etc/jmx_exporter
cp config/{kafka,mirrormaker}.yml /etc/jmx_exporter

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
cp config/ztf-alerts.service /etc/systemd/system/ztf-alerts.service

#
# MIRROR-MAKER
#
mkdir /etc/ztf
cp config/{consumer,producer}.properties /etc/ztf
cp config/ztf-mirrormaker.service /etc/systemd/system/

systemctl daemon-reload

#
# Set up kafkacat, to ease debugging
#
curl -L http://research.majuric.org/other/kafkacat -o /usr/local/bin/kafkacat
chmod +x /usr/local/bin/kafkacat

#
# Enable and start it all up
#
exit

systemctl start confluent-zookeeper
systemctl enable confluent-zookeeper

systemctl start ztf-alerts
systemctl enable ztf-alerts

systemctl start ztf-mirrormaker
systemctl enable ztf-mirrormaker
