#!/bin/bash

GRAFANA_FQDN="$1"

set -xe
cd "$(dirname $0)"

. common/functions.sh

# Generate new Let's Encrypt certificates
certbot --apache -d "$1" -m "mjuric@uw.edu" -n certonly --agree-tos
cp_with_subst config/ssl.conf /etc/httpd/conf.d/ssl.conf GRAFANA_FQDN

systemctl restart httpd
