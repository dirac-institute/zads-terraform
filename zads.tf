##
## Variables: these are the things that you can override on the command
## line, or using .tfvars files.
##

variable "do_token" {}						# Your Digital Ocean API access token

variable "domain"      { default = "test.ztf.mjuric.org" }      # The domain name of the broker. The domain must be under Digital Ocean DNS control.
								# The default will create machines in the test domain; override on the command line
								# to create in the production domain (ztf.mjuric.org).

variable "backups_dir" { default = "/dev/null" }		# The directory with saved backups for the machines. The provisioners can restore
								# these automatically (and avoid some initialization). The provisioners expect to
								# find data in ${backups_dir}/${resource_name}/latest. What's in there depends on
								# the particular droplet's bootstrap.sh, but it's usually tarballs to be untarred
								# into /.

variable "secrets_dir" { default = "/dev/null" }		# The directory with secrets for the machines. The provisioners expect to
								# find data in ${secrets_dir}/${resource_name}. What's in there depends on
								# the particular droplet's bootstrap.sh, but it's usually things like SSH keys
								# and alike.

variable "upstream_brokers"    { default = "public.alerts.ztf.uw.edu" } 
									# ^-- bootstrap.servers for upstream mirrormaker
variable "upstream_broker_net" { default = "128.95.79.19/32" }		# The network of IPAC hosts tha will see the floating IP (see below)
variable "floating_ip"         { default = "138.197.238.252" }		# The IP that IPAC hosts will see when mirrormaker connects to them

##
## You should rarely need to override these:
##

variable "broker_size" { default = "s-2vcpu-4gb" }		# Digital Ocean instance type for the broker machine
variable "monitor_size" { default = "s-2vcpu-2gb" }		# Digital Ocean instance type for the monitor machine

variable "broker_hostname"  { default = "alerts" }              # hostname of the broker
variable "monitor_hostname" { default = "status" }              # hostname of the monitor

#
# Fingerprint of the key to use for SSH-ing into the newly created machines.
# The key must be already uploaded to Digital Ocean via the web interface.
#
variable "ssh_fingerprint" { default = [ "57:c0:dd:35:2a:06:67:d1:15:ba:6a:74:4d:7c:1c:21",
					"cd:78:d0:36:19:95:59:80:66:d9:e2:c9:39:52:80:c3",
					"37:70:f2:46:82:98:fc:a4:bf:d3:8c:38:1d:dd:b8:68" ] }

#################################################################################
#
# Compute useful local variables, set up DO provider, domain
#

locals {
  broker_fqdn  = "${var.broker_hostname}.${var.domain}"
  monitor_fqdn = "${var.monitor_hostname}.${var.domain}"
}

provider "digitalocean" {
  token = "${var.do_token}"
}

resource "digitalocean_domain" "default" {
   name = "${var.domain}"
 

   lifecycle {
     # This is to prevent accidentally destroying the whole (sub)domain; there
     # may be other entries in it that are not managed by terraform.
     prevent_destroy = true
   }
}

#################################################################################
#
#  The broker machine. Runs zookeeper, kafka, mirrormaker, and Prometheus
#  metrics exporters.
#
#################################################################################

resource "digitalocean_droplet" "broker" {
  image = "centos-7-x64"
  name = "${local.broker_fqdn}"
  region = "sfo2"
  size = "${var.broker_size}"
  private_networking = true
  ipv6 = true
  monitoring = true
  ssh_keys = [
    "${var.ssh_fingerprint}"
  ]

  lifecycle {
    ignore_changes = ["volume_ids"]
  }

  # bind the floating IP to this droplet, if one has been given.
  provisioner "local-exec" {
    command = <<EOF
	test -z "${var.floating_ip}" || curl -f -X POST \
		-H 'Content-Type: application/json' \
		-H 'Authorization: Bearer ${var.do_token}' \
		-d '{"type": "assign", "droplet_id": ${digitalocean_droplet.broker.id} }' \
		https://api.digitalocean.com/v2/floating_ips/${var.floating_ip}/actions
EOF
  }

  # upload provisioning scripts and configs
  provisioner "file" {
    source      = "provisioning/broker"
    destination = "/root/provisioning"
  }

  # upload secrets
  provisioner "file" {
    source      = "${var.secrets_dir}/broker"
    destination = "/root/provisioning/secrets"
  }

  # upload any backups to be restored
  provisioner "file" {
    on_failure  = "continue"
    source      = "${var.backups_dir}/broker/latest"
    destination = "/root/provisioning/backups"
  }

  # run the provisioner
  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/bin",
      "cd /root/provisioning",
      "bash ./bootstrap.sh ${replace(local.broker_fqdn, ".", "-")} '${var.upstream_brokers}' ${var.upstream_broker_net} 2>&1 | tee /root/bootstrap.log | grep -v '^+'"
    ]
  }
}

resource "digitalocean_record" "broker" {
  depends_on = [ "digitalocean_droplet.broker" ]

  domain = "${digitalocean_domain.default.name}"
  type   = "A"
  name   = "${var.broker_hostname}"
  value  = "${digitalocean_droplet.broker.ipv4_address}"
  ttl    = "5"
}

resource "digitalocean_record" "brokerAAAA" {
  domain = "${digitalocean_domain.default.name}"
  type   = "AAAA"
  name   = "${var.broker_hostname}"
  value  = "${digitalocean_droplet.broker.ipv6_address}"
  ttl    = "5"
}

#################################################################################
#
#  The status monitoring machine (collects metrics from broker into
#  Prometheus, displays them using grafana).
#
#################################################################################

resource "digitalocean_droplet" "monitor" {

  image = "centos-7-x64"
  name = "${local.monitor_fqdn}"
  region = "sfo2"
  size = "${var.monitor_size}"
  private_networking = true
  ipv6 = true
  monitoring = true
  ssh_keys = [
    "${var.ssh_fingerprint}"
  ]

  connection {
    user = "root"
    type = "ssh"
    agent = true
    timeout = "2m"
  }

  # upload provisioning scripts and configs
  provisioner "file" {
    source      = "provisioning/monitor"
    destination = "/root/provisioning"
  }

  # upload any backups to be restored
  provisioner "file" {
    on_failure  = "continue"
    source      = "${var.backups_dir}/monitor/latest"
    destination = "/root/provisioning/backups"
  }
}

#
# Monitor provisioner requires the DNS entries to be set up (if it needs to
# bootstrap Let's Encrypt certificates), so we run it outside of the droplet
# resource entry.
#
resource "null_resource" "provision_monitor" {

  connection {
    user = "root"
    type = "ssh"
    agent = true
    timeout = "2m"
    host = "${digitalocean_record.monitor.fqdn}"
  }

  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/bin",
      "cd /root/provisioning",
      "bash ./bootstrap.sh ${local.monitor_fqdn} ${digitalocean_droplet.broker.ipv4_address_private} 2>&1 | tee /root/bootstrap.log | grep -v '^+'"
    ]
  }

}

resource "digitalocean_record" "monitor" {
  domain = "${digitalocean_domain.default.name}"
  type   = "A"
  name   = "${var.monitor_hostname}"
  value  = "${digitalocean_droplet.monitor.ipv4_address}"
  ttl    = "5"
}

resource "digitalocean_record" "monitorAAAA" {
  domain = "${digitalocean_domain.default.name}"
  type   = "AAAA"
  name   = "${var.monitor_hostname}"
  value  = "${digitalocean_droplet.monitor.ipv6_address}"
  ttl    = "5"
}
