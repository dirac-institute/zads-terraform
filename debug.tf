############################################################################
# 
# Useful for testing/debugging
#

resource "null_resource" "monitor_state" {
  count = 0

  connection {
    user = "root"
    type = "ssh"
    agent = true
    timeout = "2m"
    host = "${digitalocean_record.monitor.fqdn}"
  }

  provisioner "local-exec" {
#    when = "destroy"
    command = "bash provisioning/save-state.sh ${digitalocean_record.monitor.fqdn}"
  }
}

resource "null_resource" "test" {
  count = 1

  # assign the floating IP
  provisioner "local-exec" {
    command = <<EOF
	echo curl -f -X POST \
		-H 'Content-Type: application/json' \
		-H 'Authorization: Bearer ${var.do_token}' \
		-d '{"type": "assign", "droplet_id": ${digitalocean_droplet.broker.id} }' \
		https://api.digitalocean.com/v2/floating_ips/${digitalocean_floating_ip.broker.ip_address}/actions
EOF
  }
}
