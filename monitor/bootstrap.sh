#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker whenever the
# hosts starts.
#

set -xe

. functions.sh
. config/bootstrap

#
# set up firewall and enable it
#
yum -y install firewalld

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
yum install -y node_exporter
echo "NODE_EXPORTER_OPTS='--web.listen-address localhost:9100'" > /etc/default/node_exporter
systemctl start node_exporter

#
# Install and set up Prometheus
#
yum install -y prometheus2
mkdir -p /etc/prometheus
cp_with_subst config/prometheus.yml /etc/prometheus/prometheus.yml BROKER_PRIVATE_FQDN
#echo "PROMETHEUS_OPTS='--config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus/data --web.listen-address localhost:9090'" > /etc/default/prometheus

systemctl daemon-reload
systemctl start prometheus

#
# Install and set up Grafana
#
cp config/grafana.repo /etc/yum.repos.d/grafana.repo
yum install -y grafana

systemctl start grafana-server
systemctl status grafana-server

#
# Install Apache for proxying to the world
#
firewall-cmd --add-service=http
firewall-cmd --add-service=https
firewall-cmd --add-service=http --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --list-all

yum install httpd mod_ssl python-certbot-apache -y
systemctl start httpd
systemctl enable httpd

#
# Obtain a Let's Encrypt crtificate
#
#dry run:    certbot --apache -d monitor.ztf.mjuric.org --dry-run -m "mjuric@uw.edu" -n certonly
#real thing: certbot --apache -d monitor.ztf.mjuric.org -m "mjuric@uw.edu" -n certonly --agree-tos
cp config/certbot /etc/cron.daily/certbot
chmod +x /etc/cron.daily/certbot

cp config/ssl.conf /etc/httpd/conf.d/ssl.conf

setsebool -P httpd_can_network_connect=true

#
# Set up kafkacat, to ease debugging
#
curl -L http://research.majuric.org/other/kafkacat -o /usr/local/bin/kafkacat
chmod +x /usr/local/bin/kafkacat
