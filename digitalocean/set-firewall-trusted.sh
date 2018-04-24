#!/bin/bash
#
# Set a new list of sources for the 'trusted' firewall zone
#
# usage: set-firewall-trusted.sh <ip1> <ip2> <..>
#

# Remove old rules
for SOURCE in $(firewall-cmd --list-sources --zone=trusted); do
	firewall-cmd --zone=trusted --remove-source=$SOURCE
	firewall-cmd --zone=trusted --remove-source=$SOURCE --permanent
done

# Add new rules
for SOURCE in "$@"; do
	firewall-cmd --zone=trusted --add-source=$SOURCE
	firewall-cmd --zone=trusted --add-source=$SOURCE --permanent
done
