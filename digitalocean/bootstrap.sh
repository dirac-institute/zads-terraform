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

#
# set up firewall and enable routing
#
yum install firewalld
systemctl start firewalld
systemctl enable firewalld

cp config/kafka.xml /etc/firewalld/services/
cp config/ztf-trusted.xml /etc/firewalld/zones/

firewall-cmd --zone=public --change-interface=eth0 --permanent
firewall-cmd --zone=public --add-masquerade --permanent
firewall-cmd --zone=trusted --add-source=172.18.0.0/16 --permanent
firewall-cmd --zone=trusted --add-source=172.17.0.0/16 --permanent
systemctl reload firewalld

echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/50-ipv4-routing.conf
/sbin/sysctl -w net.ipv4.ip_forward=1

#
# Stop docker from messing with iptables
#
cp config/daemon.jon /etc/docker
systemctl restart docker

#
# Add swap space. mirrormaker runs out of memory otherwise.
#
sudo dd if=/dev/zero of=/swapfile count=16384 bs=1MiB
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile   swap    swap    sw  0   0" >> /etc/fstab

#
# Add the kafka hostnames to /etc/hosts
# I'm not sure if this is still necessary?
#
echo "127.0.0.1 kafka kafka2 kafka3" >> /etc/hosts

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
systemctl reload firewalld
systemctl enable ztf-mirrormaker
systemctl enable ztf-alerts
systemctl start ztf-mirrormaker
