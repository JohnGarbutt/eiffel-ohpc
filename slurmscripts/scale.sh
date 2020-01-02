#!/usr/bin/bash

# Create new slurm nodes
# Runs on ansible/tf control host as user "centos"
# Driven by suspend.sh/resume.sh run by SlurmUser on slurm control host (ohpc-login)

TERRAFORM=~/terraform

mode=$1
compute_changes="${@:2}"
echo $mode: $compute_changes

# load environment
. ~/.venv/bin/activate
cd ~/eiffel-ohpc/terraform_ohpc

# get existing compute instances as a space-separated list *with trailing space*:
# TODO: replace literal "ohpc-compute-" with templated name?
existing_compute=$($TERRAFORM state list openstack_compute_instance_v2.compute | grep -o "ohpc-compute-[0-9]\+" | tr "\n" " ")
echo existing compute: $existing_compute

# create target instance string:
if [ "$mode" = "resume" ]
then
  target_compute="$existing_compute$compute_changes"
  echo "target_compute (resume): $target_compute"
  # create instances
  $TERRAFORM apply -var nodenames="$target_compute" -refresh=true -auto-approve
  cat ohpc_hosts
  cd ~/eiffel-ohpc/
  ansible-playbook -v main.yml -i terraform_ohpc/ohpc_hosts
else
  for host in $compute_changes; do
	target_compute=${target_compute//$host/}
  done
  echo "target compute (suspend): target_compute"
fi
