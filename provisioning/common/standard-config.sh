#
# Disable fastestmirror -- very often it picks a slow (or invalid) mirror
# on digitalocean. Instead go directly to berkeley.edu (a fast mirror).
#
sed -i 's|^enabled=1$|enabled=0|' /etc/yum/pluginconf.d/fastestmirror.conf
sed -i 's|^mirrorlist=|#mirrorlist=|; s|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.ocf.berkeley.edu|' /etc/yum.repos.d/CentOS-Base.repo
yum clean all
yum install deltarpm

#
# Basic provisioning
#
yum install epel-release
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
yum install joe iftop screen bind-utils telnet git

#
# Firewall setup -- add eth0 to public zone and start the firewall
#
yum install firewalld
firewall-offline-cmd --zone=public --change-interface=eth0
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
