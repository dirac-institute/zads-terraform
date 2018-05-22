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
