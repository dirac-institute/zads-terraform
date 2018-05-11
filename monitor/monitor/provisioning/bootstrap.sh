#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker whenever the
# hosts starts.
#

set -xe

# grab command line arguments
GRAFANA_FQDN="$1"
BROKER_PRIVATE_FQDN="$2"

#
# Basic provisioning
#
yum -d1 -y install epel-release
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
yum -d1 -y install joe iftop screen bind-utils telnet git

##

. functions.sh

#
# set up firewall and enable it
#
yum -d1 -y install firewalld

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
dd if=/dev/zero of=/swapfile count=4 bs=512MiB
chmod 600 /swapfile
mkswap /swapfile
echo "/swapfile   swap    swap    sw  0   0" >> /etc/fstab
swapon -a

#
# Prometheus local node exporter (bind to localhost, port 9100)
#
curl -s https://packagecloud.io/install/repositories/prometheus-rpm/release/script.rpm.sh | bash
yum -d1 install -y node_exporter
echo "NODE_EXPORTER_OPTS='--web.listen-address localhost:9100'" > /etc/default/node_exporter
systemctl start node_exporter

#
# Install and set up Prometheus
#
yum -d1 install -y prometheus2
mkdir -p /etc/prometheus
cp_with_subst config/prometheus.yml /etc/prometheus/prometheus.yml BROKER_PRIVATE_FQDN
## TODO: Find a long-term solution for storing prometheus logs (see https://prometheus.io/docs/prometheus/latest/storage/)
echo "PROMETHEUS_OPTS='--config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus/data --storage.tsdb.retention=180d'" > /etc/default/prometheus

if [[ -f secrets/var-lib-prometheus.tar.gz ]]; then
	#
	# Restore from an existing data backup
	#
	mv /var/lib/prometheus /var/lib/prometheus.orig
	tar xzvf secrets/var-lib-prometheus.tar.gz -C /
fi

systemctl daemon-reload
systemctl start prometheus

#
# Install and set up Grafana
#
cp config/grafana.repo /etc/yum.repos.d/grafana.repo
yum -d1 install -y grafana

cp_with_subst config/grafana.ini /etc/grafana/grafana.ini GRAFANA_FQDN

if [[ -f secrets/var-lib-grafana.tar.gz ]]; then
	#
	# Restore from an existing data backup
	#
	mv /var/lib/grafana /var/lib/grafana.orig
	tar xzvf secrets/var-lib-grafana.tar.gz -C /
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

yum -d1 install httpd mod_ssl python-certbot-apache -y
setsebool -P httpd_can_network_connect=true

cp_with_subst config/main.conf /etc/httpd/conf.d/main.conf GRAFANA_FQDN
systemctl start httpd
systemctl enable httpd

#
# Intall or obtain a Let's Encrypt SSL crtificate
#
if [[ -f "secrets/etc-letsencrypt-$GRAFANA_FQDN.tar.gz" ]]; then
	# Restore from saved certificates
	tar xzvf "secrets/etc-letsencrypt-$GRAFANA_FQDN.tar.gz" -C /
else
	exit -1
	# Generate new ones
	certbot --apache -d "$GRAFANA_FQDN" -m "mjuric@uw.edu" -n certonly --agree-tos
fi

cp_with_subst config/ssl.conf /etc/httpd/conf.d/ssl.conf GRAFANA_FQDN
systemctl restart httpd

# automate certificate renewal
cp config/certbot /etc/cron.daily/certbot
chmod +x /etc/cron.daily/certbot


#
# Install kafkacat, to ease debugging
#
curl -L http://research.majuric.org/other/kafkacat -o /usr/local/bin/kafkacat
chmod +x /usr/local/bin/kafkacat
