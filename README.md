# Terraform scripts for the ZTF Alert Distribution System

## Quick Start

### Prerequisites

* Learn about and install [Terraform](https://www.terraform.io/intro/index.html)
  (`brew install terraform`, if you're on a Mac)
* Create a file named `do_token.auto.tfvars` with your Digital Ocean [personal
  access
  token](https://www.digitalocean.com/community/tutorials/how-to-use-the-digitalocean-api-v2).

For example:

```bash
cat do_token.auto.tfvars
cat terraform.tfvars
do_token = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
```

* Download the latest backups and Terraform state data to import into the
  brokers (the `backups/` directories and the `terraform.tfstate` file; location
  TBD on epyc).

### Standing up a system from scratch

First, make sure you have the prerequisites installed and the DO token in
`do_token.auto.tfvars` file, as discussed above. Then, run:

```bash
# Import the information about the host's domain
terraform import digitalocean_domain.default test.ztf.mjuric.org

# Create and provision the VMs
terraform apply
```

or, if you have backups, replace the last command with:

```bash
terraform apply -var "backups_dir=/path/to/backups"
```

(where `/path/to/backups` is the path where the backups are located).

Once the VMs are provisioned and created, Kafka should be running at
`alerts.test.ztf.mjuric.org:9092`, and the Grafana monitoring dashboard should
be visible at http://status.test.ztf.mjuric.org.

To enable client access to Kafka, you'll need to log into the broker host and
add your client's IP to the list of allowed IPs, e.g.:

```bash
firewall-cmd --zone=ztf-trusted --add-source=159.89.137.191
firewall-cmd --zone=ztf-trusted --add-source=159.89.137.191 --permanent
```

To have MirrorMaker access the upstream broker (`epyc`, at the moment) and start
receiving alerts, you'll need to log into `epyc` and whitelist its IP (with
commands analogous to the above).

### Destroying a system

```bash
terraform destroy --target digitalocean_droplet.broker --target digitalocean_droplet.monitor
```

## Details

### Overview

Begin by reviewing this [overview
presentation](documentation/overview-presentation.pdf) from the ZTF Alert
Distribution Readiness review.  It gives a high-level overview of the system
implemented here, and other than the change from `cloud-init` to `terraform`, it
should be mostly up-to-date.

### Architecture

The Terraform configuration files included spawn two VMs on Digital Ocean:

* The broker (named by default `alerts.test.ztf.mjuric.org`), running core
  broker functionality (Zookeeper, Kafka, and MirrorMaker). This is the machine
  that downstream brokers will be connecting to. By default, it is an
  `s-6vcpu-16gb` instance (16384 MiB RAM, 6 cores, one 320 GB SSD, and
  $80.00/month). We run a single instance of Zookeeper, Kafka, and MirrorMaker
  (all installed as yum packages).

* The status monitoring machine (named by default `status.test.ztf.mjuric.org`),
  running the monitoring database (Prometheus) and user interface (Grafana).
  This is the machine that ZADS operators use for monitoring of the system,
  including automated alerting. By default, it is an `s-1vcpu-1gb` instance
  (1024 MiB RAM, 1 core, one 25 GB SSD, and $5.00/month).

Both machines run CentOS 7.  A firewall is managed by `firewalld`.  Packages are
managed by `yum`. SELinux is on. The system does not use containers. IPv6 is
enabled. The machines use DO's weekly backup service (that retains up to four
backups). Automatic updates via `yum` are enabled (every Tuesday, at 8 am
Pacific Time).

The machines have public IPv4 and IPv6 interfaces and a private IPV4 network
running between them. The private interface is considered trusted (it's in the
`trusted` `firewalld` zone; i.e., there are no firewall-imposed limitations on
that interface). The private interface is meant to be used for all communication
between the `monitor` and the `broker`. Traffic across this interface is not
charged for. However, egress traffic across the public interface is metered and
charged for, and should be avoided when possible.

#### A note about name resolution

The configuration of both hosts try not to refer to their IPs (wherever
possible) but to hostnames defined in /etc/hosts -- `public` (for the public
IPv4 address) and `private` (for the private IPv4 address).  This is to avoid
reliance on external DNS (and allow for some additional flexibility). The
monitor host also stores the broker machine's IP as the `broker` entry in its
`/etc/hosts` file.

### Creation and Variables

Creation of the VMs and DNS entries is managed by `terraform`. All definitions
are in the `zads.tf` file. The configuration relies on several Terraform
variables -- see the top of `zads.tf` for the variables and their
documentations. The variables have safe defaults: by default, they will create
VMs in a *test* subdomain (i.e., `test.ztf.mjuric.org`). To deploy into the
operations domain, override the appropriate variables; i.e.:

```bash
terraform apply -var "domain=ztf.mjuric.org"
```

The config relies on a few variables that need to be kept secret (such as the
[Digital Ocean personal access
token](https://www.digitalocean.com/community/tutorials/how-to-use-the-digitalocean-api-v2)
used to spawn/destroy VMs).  We recommend to keep these in a file named
`do_token.auto.tfvars` (`.gitignore` is already set to ignore it, so you don't
accidentally check it into git).

### Provisioning

After VM creation, `terraform` uploads the contents of
`provisioning/<machine_name>` directory into `/root` on the machine.  It next
uploads the contents of `${backup_dir}/<machine_name` into
`/root/provisioning/backups` on the VM, if `${backup_dir}` exists. Following
these uploads, it `chdir`s into `/root/provisioning` and runs `bootstrap.sh`
scripts with parameters as given in the `zads.tf` file.

All provisioning is performed by the (host-specific) `bootstrap.sh` script. This
is a bash script that uses `yum` to install the required packages and copies
configuration files from the `/root/provisioning/config` directory to their
destinations.

The `bootstrap.sh` script is different for the two VMs, but it calls a few other
common scripts in the `provisioning/common` directory. These perform
initialization that is common to both machines.

#### Bootstrap: common elements

Common bootstrap scripts are in `provisioning/common`. They're explicitly called
from per-host `bootstrap.sh` scripts.

The common scripts include:
* [functions.sh](provisioning/common/functions.sh): defines useful common
  functions, most notably a function that fills out a template file with values
  of variables that become known at creation time (`cp_with_subst`).
* [add-swap.sh](provisioning/common/add-swap.sh): configure a swap file
* [standard-config.sh](provisioning/common/standard-config.sh): perform standard
  system configuration (timezone, `yum` tweaks, `yum` auto-updates, firewall
  setup, set up private/public hostnames).

#### Bootstrap: `broker` machine

Broker provisioning script takes one parameter -- the Kafka consumer group ID
the MirrorMaker uses to connect to the upstream broker. This should be unique
for every broker instance. By default, it's set to the FQDN of the broker
machine, with dots replaced by dashes (i.e., `alerts-test-ztf-mjuric-org`).

The provisioning script then:
* Adds swap
* Configures the firewall (adds a `kafka` firewalld service and a `ztf-trusted`
  zone).
* Installs the [Prometheus JMX
  exporter](https://github.com/prometheus/jmx_exporter) to expose the status
  metrics of Kafka, Zookeeper, and MirrorMaker to Prometheus.
* Installs the Prometheus Node Exporter, to expose generic node health metrics.
* Installs the official confluent yum repository for Kafka, and installs
  Zookeeper, Kafka, and MirrorMaker from the repository.
* Installs the configuration files for the three, including `systemd` service
  files.
* Enables and starts the `systemd` services.
* Installs [`kafkacat`](https://github.com/edenhill/kafkacat), a fast Kafka
  client, to ease testing and debugging.

**Security considerations**: The files' configuration is such that Zookeeper
only binds to `localhost`.  All Prometheus exporters are bound to the private
network interface. Kafka is bound to all available IPs, but the firewall blocks
access from any IP not permitted in the `ztf-trusted` firewalld domain.

To allow a machine to access the broker, add the IP to the `ztf-trusted` domain:

```bash
firewall-cmd --zone=ztf-trusted --add-source=159.89.137.191
firewall-cmd --zone=ztf-trusted --add-source=159.89.137.191 --permanent
```

#### Bootstrap: `monitor` machine

The monitor provisioning script takes two parameters -- its own FQDN and the
broker machine's (private) IP. The former is used to configure the Apache
virtual host, while the latter is added to `/etc/hosts` and used by Prometheus
to connect to metrics exporters running on the broker.

The provisioning script then:
* Adds a swap file.
* Configures the firewall.
* Installs the Prometheus Node Exporter to expose generic node health metrics.
* Installs and starts Prometheus from its `yum` repository ** If a Prometheus
  data backup has been made available during machine creation, it will be
  extracted and set up. Prometheus is bound to the `localhost` network interface
  (security).**
* Installs and starts Grafana from its `yum` repository ** If a Grafana data
  backup has been made available during machine creation, it will be extracted
  and set up. Grafana is bound to the `localhost` network interface (security).
  ** If not, a random admin password is created for Grafana and output to the
  screen.
* Installs and configures apache to serve as a proxy for Grafana. The setup uses
  [Let's Encrypt](https://letsencrypt.org/) to support SSL. If a backup of an
  already existing Let's Encrypt certificate has been made available during
  machine creation, it will be installed. Otherwise, after VM provisioning ends,
  you must log in and run the `letsencrypt.sh <fqdn>` script that will be
  created in the `/root/provisioning` directory to finish the process.
* Installs [`kafkacat`](https://github.com/edenhill/kafkacat), a fast Kafka
  client, to ease testing and debugging.

**Security considerations**: The files' configuration is such that Grafana and
Prometheus only bind to `localhost`.  All Prometheus exporters are bound to the
private network interface.  Apache is configured as a reverse proxy for Grafana,
with the HTTP site automatically redirecting all traffic to HTTPS.  Only `SSH`
(22), `HTTP` (80), and `HTTPS` (443) ports are open on the firewall.
