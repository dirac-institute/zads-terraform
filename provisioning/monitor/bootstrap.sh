#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker whenever the
# hosts starts.
#

set -xe

# grab command line arguments
GRAFANA_FQDN="$1"
BROKER_IP="$2"

. common/functions.sh
. common/standard-config.sh
. common/add-swap.sh 2048

#
# make the private network trusted
#
firewall-offline-cmd --zone=trusted --change-interface=eth1
systemctl restart firewalld

#
# Make the broker discoverable by name
#
echo "$BROKER_IP broker" >> /etc/hosts

#
# Prometheus local node exporter (bind to localhost, port 9100)
#
curl -s https://packagecloud.io/install/repositories/prometheus-rpm/release/script.rpm.sh | bash
yum install node_exporter
echo "NODE_EXPORTER_OPTS='--web.listen-address localhost:9100'" > /etc/default/node_exporter
systemctl start node_exporter

#
# Install and set up Prometheus
#
yum install prometheus2
mkdir -p /etc/prometheus
cp config/prometheus.yml /etc/prometheus/prometheus.yml
## TODO: Find a long-term solution for storing prometheus logs (see https://prometheus.io/docs/prometheus/latest/storage/)
echo "PROMETHEUS_OPTS='--config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus/data --storage.tsdb.retention=180d'" > /etc/default/prometheus

if [[ -f backups/var-lib-prometheus.tar.gz ]]; then
	#
	# Restore from an existing data backup
	#
	mv /var/lib/prometheus /var/lib/prometheus.orig
	tar xzvf backups/var-lib-prometheus.tar.gz -C /
fi

systemctl daemon-reload
systemctl start prometheus

#
# Install and set up Grafana
#
cp config/grafana.repo /etc/yum.repos.d/grafana.repo
yum install grafana

cp_with_subst config/grafana.ini /etc/grafana/grafana.ini GRAFANA_FQDN

if [[ -f backups/var-lib-grafana.tar.gz ]]; then
	#
	# Restore from an existing data backup
	#
	mv /var/lib/grafana /var/lib/grafana.orig
	tar xzvf backups/var-lib-grafana.tar.gz -C /
else
	#
	# Provision new
	#
	echo "No old grafana data found. Provisioning new install"
	systemctl start grafana-server

	ADMINPASS=$(openssl rand -base64 8 | tr -d =)
	curl -X PUT -H "Content-Type: application/json" -d '{ "oldPassword": "admin", "newPassword": "'"$ADMINPASS"'", "confirmNew": "'"$ADMINPASS"'"}' \
		http://admin:admin@localhost:3000/api/user/password
	echo "Grafana admin password: $ADMINPASS"
fi

systemctl start grafana-server

#
# Install Apache for proxying to the world
#
firewall-cmd --add-service=http
firewall-cmd --add-service=https
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --list-all

yum install httpd mod_ssl python-certbot-apache
setsebool -P httpd_can_network_connect=true

cp_with_subst config/main.conf /etc/httpd/conf.d/main.conf GRAFANA_FQDN
systemctl start httpd
systemctl enable httpd

#
# Intall or obtain a Let's Encrypt SSL crtificate
#
if [[ -f "backups/etc-letsencrypt-$GRAFANA_FQDN.tar.gz" ]]; then
	# Restore from saved certificates
	tar xzvf "backups/etc-letsencrypt-$GRAFANA_FQDN.tar.gz" -C /
	cp_with_subst config/ssl.conf /etc/httpd/conf.d/ssl.conf GRAFANA_FQDN
	systemctl restart httpd
else
	echo "**************************************************"
	echo "**************************************************"
	echo "**************************************************"
	echo
	echo "There were no Let's Encrypt certificates available to restore from backups."
	echo "To generate new ones, log in as root and run:"
	echo
	echo "  bash $PWD/letsencrypt.sh '$GRAFANA_FQDN'"
	echo
	echo "**************************************************"
	echo "**************************************************"
	echo "**************************************************"
fi

# automate certificate renewal
cp config/certbot /etc/cron.daily/certbot
chmod +x /etc/cron.daily/certbot

#
# Install kafkacat, to ease debugging
#
curl -L http://research.majuric.org/other/kafkacat -o /usr/local/bin/kafkacat
chmod +x /usr/local/bin/kafkacat
