#!/bin/bash -e

# Run doctl, but echo the command line to the output first
doctl()
{
	echo ./doctl "$@" 1>&2
	./doctl "$@"
}

# Create broker instance
# Usage: create_droplet <name> <region> <fqdn_public> <fqdn_private> [volumes_to_attach]
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

	# Register private domain name
	local HOSTNAME=${FQDNPRIVATE%%.*}
	local DOMAIN=${FQDNPRIVATE#$HOSTNAME.}
	dns_register "$HOSTNAME" "$DOMAIN" A    "$PRIVADDR4"
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

KAFKAPREFIX="kafka"
ZKPREFIX="zk"

REGIONS=(sfo2 sfo2 sfo2)
DOMAIN=ztf.mjuric.org
BLOCK_SIZE="200GiB"
#BLOCK_SIZE=
#INSTANCE_TYPE=s-6vcpu-16gb
#INSTANCE_TYPE=s-2vcpu-2gb
INSTANCE_TYPE=s-1vcpu-2gb

# Create brokers and data volumes
for I in "${!REGIONS[@]}"; do
	if [[ $I == 5 || $I == 5 ]]; then
		echo "Skipping $I"
		continue
	fi

	(( REPLICA=I+1 ))
	REGION=${REGIONS[$I]}

	KAFKA="$KAFKAPREFIX$REPLICA"
	ZK="$ZKPREFIX$REPLICA"
	FQDNPUBLIC="$KAFKA.$DOMAIN"
	FQDNPRIVATE="$ZK.$DOMAIN"

	DROPLET="$FQDNPUBLIC"
	VOLNAME="$KAFKA-data"

	# Create data volumes
	if [[ ! -z $BLOCK_SIZE ]]; then
		if doctl compute volume list --no-header --format Name | grep -q $VOLNAME; then
			echo "Volume $VOLNAME already exists. Skipping creation."
		else
			doctl compute volume create "$VOLNAME" --desc "$DROPLET storage" --region "$REGION" --size $BLOCK_SIZE
		fi
		VOLUME=$(doctl compute volume list --no-header --format Name,ID | grep "^$VOLNAME " | awk '{print $2}')
	fi

	# Create droplets, attach the data volume
	create_droplet $DROPLET $REGION $FQDNPUBLIC $FQDNPRIVATE $VOLUME

	# HACK: Change the private DNS entry to the public IP
	# Private networks are datacenter-internal only
	#dns_register "$ZK" "$DOMAIN" A $(doctl compute droplet list --no-header --format "PublicIPv4" "$DROPLET")
done
