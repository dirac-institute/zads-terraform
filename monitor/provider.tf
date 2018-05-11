variable "do_token" {}
variable "ssh_fingerprint" { default = "57:c0:dd:35:2a:06:67:d1:15:ba:6a:74:4d:7c:1c:21" }

provider "digitalocean" {
  token = "${var.do_token}"
}
