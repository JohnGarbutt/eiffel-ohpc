#!/usr/bin/bash

# Create new slurm nodes
# Runs on ansible/tf control host as user "centos"
# Driven by suspendstub.sh run by SlurmUser on slurm control host (ohpc-login)

TERRAFORM=~/terraform

# name of instances to suspend, space separated:
suspend_hosts=$1

# load environment
. ~/.venv/bin/activate
cd ~/eiffel-ohpc/terraform_ohpc

# destroy them
cmd="$TERRAFORM destroy "
for host in $suspend_hosts; do
	cmd+=" -target=openstack_compute_instance_v2.compute[\"$host\"]" # openstack_compute_instance_v2.compute["ohpc-compute-3"]
done
cmd+=" -auto-approve"
echo running: $cmd
$cmd
