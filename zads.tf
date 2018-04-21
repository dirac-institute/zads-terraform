##
## Variables: these are the things that you can override on the command
## line, or using .tfvars files.
##

variable "do_token" {}						# Your Digital Ocean API access token

variable "domain"           { default = "test.ztf.mjuric.org" } # The domain name of the broker. The domain must be under Digital Ocean DNS control.
								# The default will create machines in the test domain; override on the command line
								# to create in the production domain (ztf.mjuric.org).

variable "state_dir" { default = "state" }			# The directory with saved state for the machines. The provisioners expect to
								# find data in ${state_dir}/${resource_name}/latest. What's in there depends on
								# the particular droplet's bootstrap.sh, but it's usually tarballs with state or
								# secrets that can't go into the config/ directory.

##
## You should rarely need to override these:
##

variable "broker_size" { default = "s-6vcpu-16gb" }		# Digital Ocean instance type for the broker machine
variable "monitor_size" { default = "s-1vcpu-1gb" }		# Digital Ocean instance type for the monitor machine

variable "broker_hostname"  { default = "alerts" }              # hostname of the broker
variable "monitor_hostname" { default = "status" }              # hostname of the monitor

#
# Fingerprint of the key to use for SSH-ing into the newly created machines.
# The key must be already uploaded to Digital Ocean via the web interface.
#
variable "ssh_fingerprint" { default = "57:c0:dd:35:2a:06:67:d1:15:ba:6a:74:4d:7c:1c:21" }

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
   ip_address = ""

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

  # upload configs (these are versioned in git)
  provisioner "file" {
    source      = "provisioning/broker"
    destination = "/root/provisioning"
  }

  # upload secrets and state data (these are kept in a more secure location)
  provisioner "file" {
    source      = "${var.state_dir}/broker/latest"
    destination = "/root/provisioning/secrets"
  }

  # run the provisioner
  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/bin",
      "cd /root/provisioning",
      "bash ./bootstrap.sh ${replace(local.broker_fqdn, ".", "-")}"
    ]
  }

# WORK IN PROGRESS...
#  # download state before destruction
#  provisioner "local-exec" {
#    when = "destroy"
#    command = "cd ${var.broker_confdir} && bash provisioning/save-state.sh ${digitalocean_record.broker.fqdn}"
#  }
}

resource "digitalocean_record" "broker" {
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

  # upload configs
  provisioner "file" {
    source      = "provisioning/monitor"
    destination = "/root/provisioning"
  }

  # upload secrets and state
  provisioner "file" {
    source      = "${var.state_dir}/monitor/latest"
    destination = "/root/provisioning/secrets"
  }

# WORK IN PROGRESS...
#  # download state before destruction
#  provisioner "local-exec" {
#    when = "destroy"
#    command = "cd ${var.state_dir}/monitor && bash ${path.root}/provisioning/monitor/save-state.sh ${local.monitor_fqdn}"
#  }
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
      "bash ./bootstrap.sh ${local.monitor_fqdn} ${digitalocean_droplet.broker.ipv4_address_private}"
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
