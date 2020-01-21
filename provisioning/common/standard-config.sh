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
#yum install firewalld
#firewall-offline-cmd --zone=public --change-interface=eth0
#systemctl restart dbus # this helps aleviate the issue with 'ERROR: Exception DBusException: org.freedesktop.DBus.Error.AccessDenied: Connection ":1.32" is not allowed to own the service "org.fedoraproject.FirewallD1" due to security policies in the configuration file' when restarting the firewalld
#systemctl enable firewalld
#systemctl start firewalld

#
# Install Kerberos Server & Setup Kerberos Database (Initial Deployment Only!!!)
#
yum install krb5-server && mkdir /etc/keytabs
#
# !!!IMPORTANT!!!
# Once initial deployment of broker is complete the following lines of code must be disabled before destroying/rebuilding the broker
# If the following code is not disabled then the database will be re-constructed using fresh keytabs and principals.
# This will result in us having to redistribute keytabs to our partners (not good!!).
#
/usr/sbin/kdb5_util create -s -r KAFKA.SECURE -P this-is-unsecure && kadmin.local -q "add_principal -pw this-is-unsecure admin/admin"
systemctl restart krb5kdc && systemctl restart kadmin

kadmin.local -q "add_principal -randkey reader@KAFKA.SECURE"
kadmin.local -q "add_principal -randkey writer@KAFKA.SECURE"
kadmin.local -q "add_principal -randkey admin@KAFKA.SECURE"
kadmin.local -q "add_principal -randkey kafka/public.alerts.ztf.uw.edu@KAFKA.SECURE"
kadmin.local -q "add_principal -randkey zookeeper/public.alerts.ztf.uw.edu@KAFKA.SECURE"
kadmin.local -q "add_principal -randkey mirrormaker/public.alerts.ztf.uw.edu@KAFKA.SECURE"

kadmin.local -q "xst -kt /etc/keytabs/reader.user.keytab reader@KAFKA.SECURE"
kadmin.local -q "xst -kt /etc/keytabs/writer.user.keytab writer@KAFKA.SECURE"
kadmin.local -q "xst -kt /etc/keytabs/admin.user.keytab admin@KAFKA.SECURE"
kadmin.local -q "xst -kt /etc/keytabs/kafka.service.keytab kafka/public.alerts.ztf.uw.edu@KAFKA.SECURE"
kadmin.local -q "xst -kt /etc/keytabs/zookeeper.service.keytab zookeeper/public.alerts.ztf.uw.edu@KAFKA.SECURE"
kadmin.local -q "xst -kt /etc/keytabs/mirrormaker.service.keytab mirrormaker/public.alerts.ztf.uw.edu@KAFKA.SECURE"

chmod a+r /etc/keytabs/*.keytab

#
# set up inernal hostnames
#
PUBLIC_IP=$(ifconfig eth0 | grep "inet " | awk '{print $2}')
PRIVATE_IP=$(ifconfig eth1 | grep "inet " | awk '{print $2}')
echo "# Shortcuts used in config files" >> /etc/hosts
echo "$PUBLIC_IP public" >> /etc/hosts
echo "$PRIVATE_IP private" >> /etc/hosts
