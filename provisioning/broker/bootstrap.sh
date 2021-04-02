#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker whenever the
# hosts starts.
#

set -xe

GROUP_ID="$1"
BOOTSTRAP_SERVERS="$2"
UPSTREAM_BROKER_NET="$3"

. common/functions.sh
. common/standard-config.sh
. common/add-swap.sh 8192

#
# Make traffic towards the broker appear as if it's coming from the floating
# IP, so that the IPAC firewall recognizes us.
#
# We do this by adding an additional route (see https://unix.stackexchange.com/a/243704)
#
if [[ ! -z "$UPSTREAM_BROKER_NET" ]]; then
	ROUTECFG=/etc/sysconfig/network-scripts/route-eth0
	(
		# Transform the file to "old" (but more flexible) format, that will
		# then allow us to add our route.
		. "$ROUTECFG"
		eval $(ipcalc -p $ADDRESS0 $NETMASK0)
		mv "$ROUTECFG" "$ROUTECFG".bak
		echo $ADDRESS0/$PREFIX via $GATEWAY0 dev eth0 > "$ROUTECFG"
	)

	# Add the route to the upstream network that will use our anchor IP as outgoing
	GATEWAY=$(sed -n 's/GATEWAY=\(.*\)/\1/p' /etc/sysconfig/network-scripts/ifcfg-eth0)
	ANCHOR_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/anchor_ipv4/address)
	echo $UPSTREAM_BROKER_NET via $GATEWAY src $ANCHOR_IP >> "$ROUTECFG"

	echo "New network routes:"
	cat $ROUTECFG

	echo "Restarting network..."
	systemctl restart network
	echo " done."
fi

#
# Add kafka and trusted zones to firewall
#
cp config/kafka.xml /etc/firewalld/services/
cp config/ztf-trusted.xml /etc/firewalld/zones/
firewall-offline-cmd --zone=trusted --change-interface=eth1
systemctl restart firewalld

#
# Firewall whitelist updater
#
# Note: the public key in secrets/id_rsa.pub must be added as a Deployment Key to the
# github repository with the IP whitelist. Otherwise we won't be able to clone/pull it.
#
cp sync-ip-whitelist /usr/local/sbin
chmod +x /usr/local/sbin/sync-ip-whitelist
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cp secrets/id_rsa* ~/.ssh/
ssh-keyscan -H github.com >> ~/.ssh/known_hosts
restorecon -R ~/.ssh
git clone git@github.com:dirac-institute/zads-ip-whitelist-msip.git /var/lib/ip-whitelist
echo "*/5 * * * * root /usr/local/sbin/sync-ip-whitelist -f" > /etc/cron.d/ztf-firewall

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
# Utilities for broker maintenance scripts (in /opt/zads)
#

# jq, the "grep for JSON"
yum install jq

# kt (https://github.com/fgeller/kt)
curl -L http://research.majuric.org/other/kt -o /usr/local/bin/kt
chmod +x /usr/local/bin/kt

# kafkacat
curl -L http://research.majuric.org/other/kafkacat -o /usr/local/bin/kafkacat
chmod +x /usr/local/bin/kafkacat

#
# Install and configure kafka, zookeeper, and mirrormaker, and ZADS scripts
#
rpm --import https://packages.confluent.io/rpm/4.1/archive.key
cp config/confluent.repo /etc/yum.repos.d
yum install java
yum install confluent-kafka-2.11

#
# ZADS scripts and config files live in /opt/ztf
#
mkdir -p /opt/ztf/{bin,etc}

cp config/zads-{start-mirrormaker,delete-expired-topics,cron-daily} /opt/ztf/bin
chmod +x /opt/ztf/bin/*

# daily maintenance (incl. updating mirrormaker topic mirroring list, deleting old topics, etc)
cp config/zads-daily.cron /etc/cron.d/zads-daily

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
cp config/producer.properties /opt/ztf/etc
cp_with_subst config/consumer.properties /opt/ztf/etc/consumer.properties GROUP_ID BOOTSTRAP_SERVERS
cp config/ztf-mirrormaker.service /etc/systemd/system/

#
# Install Kerberos Server & Setup Kerberos Database (Initial Deployment Only!!!)
#
yum install -y krb5-server && yum install -y krb5-workstation && mkdir /etc/keytabs

cp kerberos_config/krb5.conf /etc/
cp kerberos_config/kdc.conf /var/kerberos/krb5kdc/kdc.conf
cp kerberos_config/kadm5.acl /var/kerberos/krb5kdc/kadm5.acl

cp config/kafka_server_jaas.conf /etc/kafka/
cp config/kafka_client_jaas.conf /opt/ztf/etc/
cp config/zookeeper_jaas.conf /etc/kafka/

systemctl daemon-reload
#initialize kerberos db
/usr/bin/sbin/kdb5_util create -s -r KAFKA.SECURE -P this-is-unsecure

#restore kerberos db from backup
/usr/sbin/kdb5_util load root@epyc.phys.washington.edu://data/epyc/projects/zads-terraform/public_broker/zads-terraform/kerberos_db_backup/public-kb-db-backup

#restore keytab files to /etc/keytabs/
mkdir /etc/keytabs/
scp root@epyc.phys.washington.edu://data/epyc/projects/zads-terraform/public_broker/zads-terraform/kerberos_db_backup/keytabs/*.* /etc/keytabs/

systemctl daemon-reload

# Enable and start Kerberos (Pre-requisite for Kafka)
systemctl start krb5dc
systemctl enable krb5kdc

systemctl start kadmin
systemctl enable kadmin

#
# Enable and start it all up
#

if /bin/false; then
	systemctl start ztf-zookeeper
	systemctl enable ztf-zookeeper

	systemctl start ztf-kafka
	systemctl enable ztf-kafka

	systemctl start ztf-mirrormaker
	systemctl enable ztf-mirrormaker
fi
