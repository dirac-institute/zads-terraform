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

  provisioner "file" {
    source      = "provisioning"
    destination = "/root"
  }

  provisioner "remote-exec" {
    inline = [
      "export PATH=$PATH:/usr/bin",
      "cd /root/provisioning",
      "bash ./bootstrap.sh ${digitalocean_record.monitor.fqdn} priv-zads.ztf.mjuric.org"
    ]
  }
}
