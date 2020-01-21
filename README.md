# eiffel-ohpc

Example OpenHPC slurm cluster with autoscaling built on:
https://github.com/stackhpc/ansible-role-openhpc

The cluster has a combined slurm control/login node and multiple compute nodes, some of which may be added on demand as required to service the slurm queue.

Code and instructions below are **PARTIALLY** updated for a cluster on Azure, using a sausage-cloud ansible/tf control host:

## Initial setup

In the Azure cloudshell, create a service principal using:
    ```shell
    az ad sp create-for-rbac -n openhpc --sdk-auth
    ```
Make a note of the results this returns.

On [https://compute.sausage.cloud/](https://compute.sausage.cloud/):

- Create the ansible/tf control host using:
  - Centos7.6 chipolata instance (smaller VMs are too small for the image)
  - The `gateway` network
  - A key pair from your local machine 
- Associate a floating ip

Connect to the ansible/tf control host over ssh then:
- Install wget, git, unzip, pip (via epel) and virtualenv:

  ```shell
  sudo yum install -y wget git unzip epel-release python-pip
  sudo pip install -U pip # update pip
  sudo pip install virtualenv
  ```

- Generate some entropy (else eventually everything stalls):

  ```shell
  sudo yum install -y rng-tools
  sudo systemctl start rngd
  cat /proc/sys/kernel/random/entropy_avail # should be > 200
  ```

- Clone the eiffel repo and checkout the **azure** branch:

  ```shell
  git clone https://github.com/stackhpc/eiffel-ohpc.git 
  cd ~/eiffel-ohpc
  git checkout sausage
  ```

- Setup a virtualenv with the requirements:

  ```shell
  cd ~/eiffel-ohpc
  virtualenv .venv
  . .venv/bin/activate
  pip install -U pip
  pip install -U -r requirements.txt
  ansible-galaxy install -r requirements.yml # creates /home/centos/.ansible/roles/
  ```

- Install terraform on $PATH (NB we need to be able to find this without a shell, so put it in /bin rather than adding it to ~/bin or modifying .bashrc etc):

  ```shell
  cd
  wget https://releases.hashicorp.com/terraform/0.12.18/terraform_0.12.18_linux_amd64.zip
  unzip terraform*.zip
  sudo cp terraform /bin
  ```

- Replace the galaxy stackhpc.openhpc role with a git clone and checkout appropriate branch:

  ```shell
  cd ~/.ansible/roles/
  rm -rf stackhpc.openhpc/
  git clone https://github.com/stackhpc/ansible-role-openhpc.git stackhpc.openhpc
  cd stackhpc.openhpc
  git checkout eiffel-autoscale
  ```

- Create a keypair on the ansible/tf control host using `ssh-keygen`.

- Create a credentials file in `/home/centos~/eiffel-azure/terraform_ohpc/azcreds.json` in the format:
  ```shell
  {
  "ARM_SUBSCRIPTION_ID":"YOUR_VALUE",
  "ARM_CLIENT_ID":"YOUR_VALUE",
  "ARM_CLIENT_SECRET":"YOUR_VALUE",
  "ARM_TENANT_ID":"YOUR_VALUE"
  }
  ```
  using the results from the service principal creation command above.

- Modify  `~/eiffel-ohpc/terraform_ohpc/openhpc.tf` so that:

    - `control_host` is the public IP for the ansible/terraform control host
    - `min_nodes` is the minimum number of nodes / number of persistent nodes you want
    - For compute and login nodes:
        - `key_data`is the contents of the ssh public key created on the ansible/tf control host - **NB:** NOT the keypair used to login to the ansible/tf control host - agent forwarding will not work with this autoscaling setup

- Modify ` ~/eiffel-ohpc/create.py` so that:

    - `min_nodes` matches `openhpc.tf`
    - `max_nodes` is the max number of nodes the cluster can have
    - `user` is appropriate

## Creating a cluster

On the ansible/tf control host:

Activate the venv:

```shell
cd ~/eiffel-ohpc/terraform_ohpc
. ~/eiffel-ohpc/.venv/bin/activate
```

Deploy the instances using terraform:

```shell
cd ~/eiffel-ohpc/terraform_ohpc
terraform init
terraform apply
```

Configure them with ansible:

```shell
cd ~/eiffel-ohpc/
ansible-playbook main.yml -i terraform_ohpc/ohpc_hosts
```

To delete the cluster:

```shell
cd ~/eiffel-ohpc/terraform_ohpc
~/terraform destroy
```

To modify a cluster after changing its definition config just re-run the above terraform/ansible commands (the `init` command is only required once). If only the powersaving scripts have been modified these can be redeployed using:

```shell
cd ~/eiffel-ohpc/
ansible-playbook scaling.yml -i terraform_ohpc/ohpc_hosts
```

## Logging into slurm nodes

For the slurm control/login node just go through the ansible/tf control host first, e.g.:

```shell
ssh centos@93.186.40.108 # ansible/tf control host
ssh centos@93.186.40.117 # ohpc-login
```

To login to compute nodes (e.g. for debugging) go from the ansible/tf control host but then proxy through the slurm head node, e.g.:

```shell
ssh centos@93.186.40.108 # ansible/tf control host
ssh -o ProxyCommand="ssh centos@93.186.40.117 -W %h:%p" 10.0.0.143 # first IP ohpc-login, 2nd IP = ohpc-compute-N
```

## Restarting slurm control daemon
If a clean restart is required to fix failed autoscaling, from the slurm control/login node use `top -u slurm -n 1` to find the slurmctld process, kill -9 it, then run `sudo /sbin/slurmctld -c`. The `-c` argument forces it to ignore any partition/job state files so all jobs will be lost.

## Using a snapshot
To significantly speed up build of compute nodes during autoscaling, create a snapshot of a running compute node and rebuild the cluster using that image:

1. Create the cluster as above

2. Log in to one of the compute nodes (see above)

3. Run the following to anonymise the VM:

   ```shell
   sudo service slurmd stop
   sudo systemctl disable slurmd
   vi /etc/hosts # remove openhpc-* hosts, but leave localhost
   sudo rm /etc/slurm/slurm.conf
   sudo rm /var/log/slurm*
   ```

4. In the sausagecloud OpenStack GUI, pick "snapshot" on the above instance, and wait for it to finish saving (may require a refresh of the page).

5. Modify the compute image in `terraform_ohpc/ohpc.tf` to use the above image - **NB** do not change the login image!

6. Delete the cluster and recreate it following the instructions above.
