#!/bin/bash

echo firewall-cmd --zone=ztf-trusted --add-source=$(dig +short kafka1.ztf.mjuric.org) --add-source=$(dig +short kafka2.ztf.mjuric.org) --add-source=$(dig +short kafka3.ztf.mjuric.org)
