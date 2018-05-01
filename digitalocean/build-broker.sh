#!/bin/bash -e

# Run doctl, but echo the command line to the output first
doctl()
{
	echo ./doctl "$@" 1>&2
	./doctl "$@"
}

# Create broker instance
# Usage: create_droplet <name> <region> <fqdn_public> [fqdn_private [volumes_to_attach]]
# Returns: droplet ID
create_droplet()
{
	local NAME="$1"
	local REGION="$2"
	local FQDNPUBLIC="$3"
	local FQDNPRIVATE="$4"
	local VOLUMES="$5"

	test -z $VOLUMES && VOLARG= || VOLARG="--volumes $VOLUMES"

	# check if this droplet exists, and delete if so
	ID=$(doctl compute droplet list --no-header --format "ID" "$NAME")
	if [[ ! -z $ID ]]; then
		if [[ $CLOBBER == 1 ]]; then
			doctl compute droplet delete "$ID"
		else
			echo "Droplet $NAME already exists; refusing to delete it as \$CLOBBER != 1" 1>&2
			exit -1
		fi
	fi

	# create server
	doctl compute droplet create "$NAME" \
		--size "$INSTANCE_TYPE" --image centos-7-x64 --region "$REGION" --enable-ipv6 --enable-private-networking --enable-monitoring \
		$VOLARG --user-data-file cloud-config.yaml \
		--wait

	# Get our IPs
	IFS=' ' read ID ADDR4 PRIVADDR4 ADDR6 <<< $(doctl compute droplet list --no-header --format "ID,PublicIPv4,PrivateIPv4,PublicIPv6" "$NAME")

	# Register public domain name
	local HOSTNAME=${FQDNPUBLIC%%.*}
	local DOMAIN=${FQDNPUBLIC#$HOSTNAME.}
	dns_register "$HOSTNAME" "$DOMAIN" A    "$ADDR4"
	dns_register "$HOSTNAME" "$DOMAIN" AAAA "$ADDR6"

	if [[ ! -z $FQDNPRIVATE ]]; then
		# Register private domain name
		local HOSTNAME=${FQDNPRIVATE%%.*}
		local DOMAIN=${FQDNPRIVATE#$HOSTNAME.}
		dns_register "$HOSTNAME" "$DOMAIN" A    "$PRIVADDR4"
	fi
}

# Add DNS entries
# Usage: dns_register <hostname> <domain> <rectype> <ip>
dns_register()
{
	local HOSTNAME="$1"
	local DOMAIN="$2"
	local RECTYPE="$3"
	local IP="$4"

	# Delete any old entries for this FQDN
	doctl compute domain records list "$DOMAIN" --no-header --format ID,Type,Name | while read RECID TYPE NAME; do
		if [[ "$TYPE" == "$RECTYPE" && "$NAME" == "$HOSTNAME" ]]; then
			doctl compute domain records delete "$DOMAIN" "$RECID" -f
		fi
	done

	# Add the new entry
	doctl compute domain records create "$DOMAIN" --record-type "$RECTYPE" --record-name "$HOSTNAME" --record-ttl 60 --record-data "$IP"
}

###

CLOBBER=1

REGION=sfo2
#DROPLET=alerts.ztf.mjuric.org
DROPLET=zads.ztf.mjuric.org
#INSTANCE_TYPE=s-6vcpu-16gb
#INSTANCE_TYPE=s-2vcpu-2gb
#INSTANCE_TYPE=s-1vcpu-2gb
INSTANCE_TYPE=s-4vcpu-8gb

###

create_droplet $DROPLET $REGION $DROPLET "priv-$DROPLET"
