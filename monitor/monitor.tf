variable "do_token" {}

variable "broker_confdir"  { default = "broker" }
variable "monitor_confdir" { default = "monitor" }

variable "ssh_fingerprint" { default = "57:c0:dd:35:2a:06:67:d1:15:ba:6a:74:4d:7c:1c:21" }

provider "digitalocean" {
  token = "${var.do_token}"
}

resource "digitalocean_droplet" "monitor" {

  image = "centos-7-x64"
  name = "status.ztf.mjuric.org"
  region = "sfo2"
  size = "s-1vcpu-1gb"
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

}

resource "digitalocean_domain" "default" {
   name = "ztf.mjuric.org"
   ip_address = ""

   lifecycle {
     prevent_destroy = true
   }
}

resource "digitalocean_record" "monitor" {
  domain = "${digitalocean_domain.default.name}"
  type   = "A"
  name   = "status"
  value  = "${digitalocean_droplet.monitor.ipv4_address}"
  ttl    = "5"
}

resource "digitalocean_record" "monitorAAAA" {
  domain = "${digitalocean_domain.default.name}"
  type   = "AAAA"
  name   = "status"
  value  = "${digitalocean_droplet.monitor.ipv6_address}"
  ttl    = "5"
}

resource "null_resource" "monitor_provisioning" {
  connection {
    user = "root"
    type = "ssh"
    agent = true
    timeout = "2m"
    host = "${digitalocean_record.monitor.fqdn}"
  }

  # upload configs
  provisioner "file" {
    source      = "${var.monitor_confdir}/provisioning"
    destination = "/root"
  }

  # upload secrets and state
  provisioner "file" {
    source      = "${var.monitor_confdir}/data/latest"
    destination = "/root/provisioning/secrets"
  }

  # run provisioner
  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/bin",
      "cd /root/provisioning",
      "bash ./bootstrap.sh ${digitalocean_record.monitor.fqdn} priv-zads.ztf.mjuric.org"
    ]
  }

  # download state before destruction
  provisioner "local-exec" {
    when = "destroy"
    command = "cd ${var.monitor_confdir} && bash provisioning/save-state.sh ${digitalocean_record.monitor.fqdn}"
  }
}

resource "null_resource" "monitor_state" {
  count = 0
  depends_on = ["null_resource.monitor_provisioning"]

  connection {
    user = "root"
    type = "ssh"
    agent = true
    timeout = "2m"
    host = "${digitalocean_record.monitor.fqdn}"
  }

  provisioner "local-exec" {
#    when = "destroy"
    command = "cd ${var.monitor_confdir} && bash provisioning/save-state.sh ${digitalocean_record.monitor.fqdn}"
  }
}
