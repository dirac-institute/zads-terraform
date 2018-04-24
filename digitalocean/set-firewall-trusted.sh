#!/bin/bash

# Remove old rules
for SOURCE in $(firewall-cmd --list-sources --zone=trusted); do
	echo firewall-cmd --zone=ztf-trusted --remove-source=$SOURCE
done

# Add new rules
for SOURCE in "$@"; do
	firewall-cmd --zone=ztf-trusted --add-source=$SOURCE
done
