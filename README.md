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

TODO: expand and contract playbooks.
