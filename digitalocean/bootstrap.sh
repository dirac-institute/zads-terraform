#
# Setting up a host to run the ZTF broker. These instructions will set up 
# the firewall, plus services necessary to boot the broker containers whenever the
# hosts starts.
#
# Assumptions:
#  * the host runs CentOS 7
#  * docker has been installed
#  * docker-compose has been installed in /usr/local/bin/docker-compose
#    * /root/ztf_prod/docker-compose.yml is the compose file describing the containers
#  * the internal docker network is called ztf_prod_default
#  * the docker networks involved are 172.17/16 and 172.18/16
#

DOCKER_SUBNET="172.28.0.0/16"

#
# set up firewall and enable routing
#
yum -y install firewalld
systemctl start firewalld
systemctl enable firewalld

cp config/kafka.xml /etc/firewalld/services/
cp config/ztf-trusted.xml /etc/firewalld/zones/

firewall-cmd --zone=public --change-interface=eth0 --permanent
firewall-cmd --zone=public --add-masquerade --permanent
firewall-cmd --zone=trusted --add-source="$DOCKER_SUBNET" --permanent
systemctl reload firewalld

echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/50-ipv4-routing.conf
/sbin/sysctl -w net.ipv4.ip_forward=1

#
# Install docker and stop it from messing with iptables
#
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum -y install docker-ce
cp config/daemon.jon /etc/docker
systemctl start docker
systemctl enable docker

#
# Install docker compose
#
curl -L https://github.com/docker/compose/releases/download/1.21.0/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
docker-compose --version

#
# Add swap space. mirrormaker runs out of memory otherwise.
#
dd if=/dev/zero of=/swapfile count=16 bs=512MiB
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile   swap    swap    sw  0   0" >> /etc/fstab

#
# Add the kafka hostnames to /etc/hosts
# I'm not sure if this is still necessary?
#
#IP=$(ifconfig eth0 | grep "inet " | awk '{print $2}')
#echo "$IP kafka kafka2 kafka3" >> /etc/hosts

#
# Install the application (kafka)
#
mkdir -p /var/lib/zookeeper/{data,log} /var/lib/kafka/data
docker network create ztf_broker --subnet="$DOCKER_SUBNET"

#
# Have the ztf-alerts service log into its own file
#
cp config/ztf-alerts.conf /etc/rsyslog.d/
systemctl restart rsyslog

#
# Set up systemd services that will start mirrormaker and kafka
#
cp config/ztf-alerts.service /etc/systemd/system/
cp config/ztf-mirrormaker.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable ztf-mirrormaker
systemctl enable ztf-alerts
systemctl start ztf-mirrormaker
