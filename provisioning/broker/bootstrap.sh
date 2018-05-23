#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker whenever the
# hosts starts.
#

set -xe

GROUP_ID="$1"

. common/functions.sh
. common/standard-config.sh
. common/add-swap.sh 8192

#
# Make all traffic appear as if it's coming from the floating IP, so that the IPAC
# broker recognizes us.
#
# We do this by modifying the default route to include a 'src <anchor_ip>'
# stanza; i.e., this is equivalent to something like 'ip route change
# default via gateway src 10.46.0.9'
#
if /bin/true; then
	IFCFG=/etc/sysconfig/network-scripts/ifcfg-eth0
	ROUTECFG=/etc/sysconfig/network-scripts/route-eth0

	GATEWAY=$(sed -n 's/GATEWAY=\(.*\)/\1/p' "$IFCFG")
	ANCHOR_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/anchor_ipv4/address)

	# Have all outgoing connections appear to come from the anchor IP...
	echo "SRCADDR=$ANCHOR_IP" >> "$IFCFG"

	# ... except for the Metadata service IP (which doesn't work otherwise)
	cat >> /etc/sysconfig/network-scripts/route-eth0 <<-EOF
		ADDRESS1=169.254.169.254
		GATEWAY1=$GATEWAY
		NETMASK1=255.255.255.255
	EOF

	systemctl restart network
fi

#
# Add kafka and trusted zones to firewall
#
cp config/kafka.xml /etc/firewalld/services/
cp config/ztf-trusted.xml /etc/firewalld/zones/
firewall-offline-cmd --zone=trusted --change-interface=eth1
systemctl restart firewalld

#
# Prometheus JMX exporter, for exporting JVM (JMX) metrics from kafka and mirrormaker
#   Kafka and Mirrormaker .service files call /opt/jmx_exporter/jmx_prometheus_javaagent.jar
#
mkdir -p /opt/jmx_exporter
curl -L https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.3.0/jmx_prometheus_javaagent-0.3.0.jar -o /opt/jmx_exporter/jmx_prometheus_javaagent.jar
mkdir /etc/jmx_exporter
cp config/{zookeeper,kafka,mirrormaker}.yml /etc/jmx_exporter

#
# Kafka exporter (for monitoring group offsets)
#
## mkdir -p /opt/kafka_exporter/bin
## curl -LO https://github.com/danielqsj/kafka_exporter/releases/download/v1.1.0/kafka_exporter-1.1.0.linux-amd64.tar.gz
## tar xzvf kafka_exporter-1.1.0.linux-amd64.tar.gz
## mv kafka_exporter-1.1.0.linux-amd64/kafka_exporter /opt/kafka_exporter/bin

#
# Prometheus node exporter (bind to private addres, port 9100)
#
curl -s https://packagecloud.io/install/repositories/prometheus-rpm/release/script.rpm.sh | bash
yum install node_exporter
echo "NODE_EXPORTER_OPTS='--web.listen-address private:9100'" > /etc/default/node_exporter
systemctl start node_exporter

#
# Install and configure kafka, zookeeper, and mirrormaker
#
rpm --import https://packages.confluent.io/rpm/4.1/archive.key
cp config/confluent.repo /etc/yum.repos.d
yum install java
yum install confluent-kafka-2.11

#
# ZOOKEEPER
#
cp config/zookeeper.properties /etc/kafka/zookeeper.properties
cp config/ztf-zookeeper.service /etc/systemd/system/ztf-zookeeper.service

#
# KAFKA
#
cp config/server.properties /etc/kafka/server.properties
cp config/ztf-kafka.service /etc/systemd/system/ztf-kafka.service

#
# MIRROR-MAKER
#
mkdir -p /etc/ztf
cp config/producer.properties /etc/ztf
cp_with_subst config/consumer.properties /etc/ztf/consumer.properties GROUP_ID
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

systemctl start ztf-zookeeper
systemctl enable ztf-zookeeper

systemctl start ztf-kafka
systemctl enable ztf-kafka

systemctl start ztf-mirrormaker
systemctl enable ztf-mirrormaker
