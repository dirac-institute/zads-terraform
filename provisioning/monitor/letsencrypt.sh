#!/bin/bash

GRAFANA_FQDN="$1"

set -xe
. "$(dirname $0)/functions.sh"

# Generate new Let's Encrypt certificates
certbot --apache -d "$1" -m "mjuric@uw.edu" -n certonly --agree-tos
cp_with_subst config/ssl.conf /etc/httpd/conf.d/ssl.conf GRAFANA_FQDN

systemctl restart httpd
