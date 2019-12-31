#!/usr/bin/bash

# Create new slurm nodes
# Runs on ansible/tf control host as user "centos"
# Driven by resumestub.sh run by SlurmUser on slurm control host (ohpc-login)

TERRAFORM=~/terraform

# new compute instance hostnames:
new_compute=$@
echo new compute: $new_compute

# load environment
. ~/.venv/bin/activate
cd ~/eiffel-ohpc/terraform_ohpc

# get existing compute instances as a space-separated list *with trailing space*:
# TODO: replace literal "ohpc-compute-" with templated name?
existing_compute=$($TERRAFORM state list openstack_compute_instance_v2.compute | grep -o "ohpc-compute-[0-9]\+" | tr "\n" " ")
echo existing compute: $existing_compute

# create target instance string:
target_compute="$existing_compute$new_compute"
echo target_compute: $target_compute

# create instances
$TERRAFORM apply -var nodenames="$target_compute" -refresh=true -auto-approve

# configure instances
cd ~/eiffel-ohpc/
ansible-playbook create.yml -i terraform_ohpc/ohpc_hosts
ansible-playbook beegfs.yml -i terraform_ohpc/ohpc_hosts
ansible-playbook slurmscale.yml -i terraform_ohpc/ohpc_hosts