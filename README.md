# eiffel-ohpc

Example OpenHPC cluster built on:
https://github.com/stackhpc/ansible-role-openhpc

## Install

You may find this useful to run the above ansible-playbook command:

    virtualenv .venv
    . .venv/bin/activate
    pip install -U pip
    pip install -U -r requirements.txt
    ansible-galaxy install -r requirements.yml

## Inventory generation

You may find this useful to generate an inventory:

    . openrc
    ./get-servers.py > hosts

## Usage

You can create a cluster by doing:

    ansible-playbook create.yml -i hosts

## Terraform

Download the latest and unzip it:
https://www.terraform.io/downloads.html

    cd terraform_examples
    terraform init
    terraform import openstack_containerinfra_cluster_v1.testk8s b0125e63-90e1-4f4e-8515-3bd109d07b87
    terraform plan
    terraform apply
