#
# Set timezone to PDT
#
timedatectl set-timezone America/Los_Angeles

#
# We don't enable this on DO (if it's left enabled, then
# `systemd status` reports the overall state as "degraded")
#
systemctl disable kdump

#
# Disable fastestmirror -- very often it picks a slow (or invalid) mirror
# on digitalocean. Instead go directly to berkeley.edu (a fast mirror).
#
sed -i 's|^enabled=1$|enabled=0|' /etc/yum/pluginconf.d/fastestmirror.conf
sed -i 's|^mirrorlist=|#mirrorlist=|; s|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.ocf.berkeley.edu|' /etc/yum.repos.d/CentOS-Base.repo
yum clean all
yum install deltarpm

#
# Update the base image
#
#yum update

#
# Set up automatic updates ("patch Tuesday, every 8am").
#
cat > /etc/cron.d/yum-cron-tuesday <<-EOT
	SHELL=/bin/bash
	PATH=/sbin:/bin:/usr/sbin:/usr/bin
	MAILTO=root
	0 8 * * tue root  yum -y update >/dev/null
EOT

#
# Basic provisioning
#
yum install epel-release
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7
yum install joe iftop screen bind-utils telnet git

#
# Firewall setup (This has been disbaled since DO firewall is effective) -- add eth0 to public zone and start the firewall
#
yum install firewalld
firewall-offline-cmd --zone=public --change-interface=eth0
systemctl restart dbus # this helps aleviate the issue with 'ERROR: Exception DBusException: org.freedesktop.DBus.Error.AccessDenied: Connection ":1.32" is not allowed to own the service "org.fedoraproject.FirewallD1" due to security policies in the configuration file' when restarting the firewalld
systemctl enable firewalld
systemctl start firewalld


#
# set up inernal hostnames
#
PUBLIC_IP=$(ifconfig eth0 | grep "inet " | awk '{print $2}')
PRIVATE_IP=$(ifconfig eth1 | grep "inet " | awk '{print $2}')
echo "# Shortcuts used in config files" >> /etc/hosts
echo "$PUBLIC_IP public" >> /etc/hosts
echo "$PRIVATE_IP private" >> /etc/hosts
