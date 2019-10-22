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

## Create Infrastructure

First download Terraform:

    cd terraform_ohpc
    export terraform_version="0.12.12"
    wget https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip
    unzip terraform_${terraform_version}_linux_amd64.zip

Now you can get Terraform to create the infrastructure:

    cd terraform_ohpc
    ./terraform init
    ./terraform apply

## Usage

You can create a cluster by doing:

    ansible-playbook create.yml -i terraform_ohpc/ohpc_hosts

## Terraform

Download the latest and unzip it:
https://www.terraform.io/downloads.html

    cd terraform_examples
    terraform init
    terraform import openstack_containerinfra_cluster_v1.testk8s b0125e63-90e1-4f4e-8515-3bd109d07b87
    terraform plan
    terraform apply

# Ansible
