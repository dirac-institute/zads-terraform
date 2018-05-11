# Terraform scripts for the ZTF Alert Distribution System

## Prerequisites

* Terraform (`brew install terraform`)
* Create a file named `do_token.auto.tfvars` with your Digital Ocean
  personal access token. For example:
```
$ cat do_token.auto.tfvars
do_token = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
```
* Download the latest state to import into the brokers (the `data/`
  directories and the `terraform.tfstate` file; location TBD).

## Importing the domain information

```
terraform import digitalocean_domain.default ztf.mjuric.org
```

## Building the alert broker

```
terraform apply
```

## Destroying the system

```
terraform destroy
```
