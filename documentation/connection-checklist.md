# A checklist to test your broker connections

Note: the examples below assume you're using `bash`. Adjust the command lines to your shell, if necessary.

## Whitelist your external IP

At present, we authorize connections by whitelisting your IP. It's important that the IP you send us is an externally visible one, and not an internally used IP. An simple way to verify you sent us the right IP is using the [ifconfig.co](https://ifconfig.co/) service:

```
$ curl ifconfig.co
128.95.79.19
```

## Basic network connectivity

If your IP is authorized, you should be able to access port 9092. Try:

```
telnet public.alerts.ztf.uw.edu 9092
```

to test basic connectivity. If you need to get an IP (or a small -- say /24 -- network) whitelisted, e-mail the ztf-broker-ops mailing list.

## Kafka connectivity

To test the ability to query the Kafka broker and consume messages, you will need a Kafka client. 
I recommend starting with [`kafkacat`](https://github.com/edenhill/kafkacat), a simple `cat`-like
client for Kafka.

Obtaining `kafkacat`:
* With conda: `conda install -c conda-forge kafkacat`
* Pre-built for Linux (RHEL7): `curl -LO http://research.majuric.org/other/kafkacat && chmod +x kafkacat`

Listing all available topics:
```
[mjuric@epyc ~]$ kafkacat -b public.alerts.ztf.uw.edu -L
Metadata for all topics (from broker 0: public.alerts.ztf.uw.edu:9092/0):
 1 brokers:
  broker 0 at public.alerts.ztf.uw.edu:9092
 5 topics:
  topic "ztf_20180528_programid1" with 14 partitions:
    partition 8, leader 0, replicas: 0, isrs: 0
    partition 11, leader 0, replicas: 0, isrs: 0
    partition 2, leader 0, replicas: 0, isrs: 0
    partition 5, leader 0, replicas: 0, isrs: 0
    partition 4, leader 0, replicas: 0, isrs: 0
    partition 13, leader 0, replicas: 0, isrs: 0
    partition 7, leader 0, replicas: 0, isrs: 0
    partition 1, leader 0, replicas: 0, isrs: 0
    partition 10, leader 0, replicas: 0, isrs: 0
    partition 9, leader 0, replicas: 0, isrs: 0
    partition 3, leader 0, replicas: 0, isrs: 0
    partition 12, leader 0, replicas: 0, isrs: 0
    partition 6, leader 0, replicas: 0, isrs: 0
    partition 0, leader 0, replicas: 0, isrs: 0
  topic "ztf_20180531_programid1" with 14 partitions:
    partition 8, leader 0, replicas: 0, isrs: 0
    partition 11, leader 0, replicas: 0, isrs: 0
    partition 2, leader 0, replicas: 0, isrs: 0
    partition 5, leader 0, replicas: 0, isrs: 0
    partition 13, leader 0, replicas: 0, isrs: 0
...
```

## Testing download speeds

For a quick test of download speed, we use the [Pipe Viewer](http://www.ivarch.com/programs/pv.shtml) (`pv`) utility.

Obtaining `pv`:
* With conda: `conda install -c conda-forge pv`
* Pre-built for Linux (RHEL7): `curl -LO http://research.majuric.org/other/pv && chmod +x pv`

Test consumption speed:
```
$ kafkacat -b public.alerts.ztf.uw.edu -t ztf_20180528_programid1 -o beginning -e | pv -r -b -a -i 5 > /dev/null
% Auto-selecting Consumer mode (use -P or -C to override)
 210MiB [7.52MiB/s] [5.99MiB/s]
```
(we're aiming for 1MByte/sec, sustained).

Note: IPv6 connectivity is turned on and should work. If you're having issues  (e.g., your networking is
misconfigured and your host attempts to go over IPv6 though it can't, or your IPv6 address
hasn't been whitelisted), add `-X broker.address.family=v4` option to the `kafkacat` command line
to force IPv4.

## Consuming with ZTF's demo client

The experiments above verified the ability to contact and consume alerts over Kafka, but didn't 
attempt to parse them. The easiest way to begin with parsing is by using ZTF's demo client:

Obtaining:
* Docker: See instructions at https://github.com/ZwickyTransientFacility/alert_stream/
* With `conda`: 
```
conda install -c conda-forge fastavro python-avro python-confluent-kafka

git clone https://github.com/ZwickyTransientFacility/ztf-avro-alert
git clone https://github.com/ZwickyTransientFacility/alert_stream
cd alert_stream/
export PYTHONPATH="$PYTHONPATH:$PWD/python"
```

Consuming alerts from `ztf_20180528_programid1` with alert contents being printed out to the screen:
```
HOSTNAME=$(hostname) python bin/printStream.py public.alerts.ztf.uw.edu ztf_20180528_programid1
```

Note: you may see error messages about not being able to connect to `ipv4#206.189.209.83:9093` of `ipv4#206.189.209.83:9094` -- this is a known bug in the client (a fix is on the way).
