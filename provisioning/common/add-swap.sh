#
# Add swap space, just in case
#
dd if=/dev/zero of=/swapfile count=$1 bs=1MiB
chmod 600 /swapfile
mkswap /swapfile
echo "/swapfile   swap    swap    sw  0   0" >> /etc/fstab
swapon -a
