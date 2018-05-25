#!/bin/bash
#
# Start MirrorMaker mirroring of alert topics from the last $NDAYS, relative to the current point in time.
# Does so by constructing a regular expression that will whitelist topic names for the last $NDAYS days.
#

NDAYS=${ZTF_MIRROR_DAYS:-7}

# Construct the date part of the regular expression
DATES=$(for i in $(seq 0 $(($NDAYS-1)) ) ; do env TZ=UTC date --date="-${i} day" +"%Y%m%d" ; done | paste -sd\|)

# Run mirrormaker
exec /usr/bin/kafka-mirror-maker --consumer.config /etc/ztf/consumer.properties --producer.config /etc/ztf/producer.properties --whitelist="^ztf_(${DATES})_programid1\$" --num.streams=16
