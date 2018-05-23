#
# Production system settings
#
domain              = "public.ztf.mjuric.org"
backups_dir         = "backups"
upstream_brokers    = "ztfalerts01.ipac.caltech.edu:9092,ztfalerts02.ipac.caltech.edu:9092,ztfalerts03.ipac.caltech.edu:9092"
upstream_broker_net = "134.4.57.0/24"
floating_ip         = "167.99.25.103"
