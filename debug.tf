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
