#!/bin/bash

FQDN="$1"

# Fail if any command, and also if any command in a pipe fails
set -e
set -o pipefail

# execute a remote command
remote() { echo "Running: $@" 1>&2; ssh -oLogLevel=error -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null root@"$FQDN" "$@"; }

STATESUBDIR="$(date +"%Y-%d-%m-%T%z")"
STATEDIR="data/$STATESUBDIR"
echo "Saving state tarballs to $STATEDIR"
mkdir -p "$STATEDIR"

remote systemctl stop grafana-server prometheus
remote tar czf - -C / etc/letsencrypt     | cat > "$STATEDIR/etc-letsencrypt-$FQDN.tar.gz"
remote tar czf - -C / var/lib/grafana     | cat > "$STATEDIR/var-lib-grafana.tar.gz"
remote tar czf - -C / var/lib/prometheus  | cat > "$STATEDIR/var-lib-prometheus.tar.gz"

rm -f data/latest
ln -s "$STATESUBDIR" data/latest

ls -l "data/latest/"
