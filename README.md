# eiffel-ohpc

Example OpenHPC slurm cluster with autoscaling built on:
https://github.com/stackhpc/ansible-role-openhpc

The cluster has a combined slurm control/login node and multiple compute nodes, some of which may be added on demand as required to service the slurm queue.

Code and instructions below are for [vss](https://vss.cloud.private.cam.ac.uk/) but other OpenStack clouds will be similar.

## Initial setup

On the [vss web dashboard](https://vss.cloud.private.cam.ac.uk/), from Project / Compute / Access & Security / API Access download an OpenStack RC File **V3**. Upload that to ilab-gate.
TODO: this will need fixing for automation.

On `ilab-gate`, create an ansible/terraform control host `eiffel-vss-ctl` and associated infrastructure:
- If you want to be able to log into the control host from elsewhere, copy the public keyfile you want to use to e.g. `~/.ssh/id_rsa_mykeypair.pub`
- Clone this repo and checkout branch `vss`.
- Now deploy the ansible/terraform control host `eiffel-vss-ctl` and infrastructure using terraform:

  ```shell
  source ~/vss-openrc-v3.sh # will prompt for password
  cd /ilab-home/$USER/eiffel-ohpc/terraform_ctl
  terraform init
  terraform apply -var ssh_key_file=~/.ssh/id_rsa_mykeypair # note no .pub
  ```
- From the machine with the private key for `mykeypair`, log into ansible/terraform control host `eiffel-vss-ctl` using the IP it outputs as user `centos`.

On the ansible/tf control host `eiffel-vss-ctl`:
Upload the openstack RC file V3 to TODO: ??? and add your password at `export OS_PASSWORD`, deleting the prompt for this.

- Install wget, git, unzip, pip (via epel) and virtualenv:

  ```shell
  sudo yum install -y wget git unzip epel-release
  sudo yum install -y python-pip
  sudo pip install -U pip # update pip
  sudo pip install virtualenv
  ```

- Generate some entropy (else eventually everything stalls):

  ```shell
  sudo yum install -y rng-tools
  sudo systemctl start rngd
  sleep 5 # wait for a bit for start ...
  cat /proc/sys/kernel/random/entropy_avail # should be > 200
  ```

  Clone the eiffel repo and checkout the **vss** branch:

  ```shell
  git clone https://github.com/stackhpc/eiffel-ohpc.git 
  cd ~/eiffel-ohpc
  git checkout vss
  ```

- Use the variables in the OpenStack RC file to create a [clouds.yaml](https://docs.openstack.org/openstacksdk/latest/user/config/configuration.html) file in `~/eiffel-ohpc/terraform_ohpc/`. The cloud name should be `vss` and you need to include a `password` entry with your openstack password.


  At this point you can swap to viewing this README on the ansible/tf control host rather than ilab-gate :-).

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

- Create a keypair on the ansible/tf control host using `ssh-keygen` and upload the public key to openstack through the sausage web GUI.

- If required, modify  `~/eiffel-ohpc/terraform_ohpc/openhpc.tf` so that:

    - `control_host` is the public IP for the ansible/terraform control host `eiffel-vss-ctl`
    - `min_nodes` is the minimum number of nodes / number of persistent nodes you want
    - `keypair` is the name of the keypair created on the ansible/tf control host - **NB:** NOT the keypair used to login 
      to the ansible/tf control host - agent forwarding will not work with this autoscaling setup
    
- Modify ` ~/eiffel-ohpc/create.py` so that:

    - `min_nodes` matches `openhpc.tf`
    - `max_nodes` is the max number of nodes the cluster can have

- Add `172.24.44.2 vss.cloud.private.cam.ac.uk` to `/etc/hosts`. FIXME:

## Creating a cluster

On the ansible/tf control host:

Source the OpenStack RC file.

Activate the venv:

```shell
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
If a clean restart is required to fix failed autoscaling, from the slurm control/login node run `sudo scontrol slurmctld stop`, check its stopped using `top -u slurm -n 1`, then run `sudo /sbin/slurmctld -c`. The `-c` argument forces it to ignore any partition/job state files so all jobs will be lost.

## Using a snapshot
To significantly speed up build of compute nodes during autoscaling, create a snapshot of a running compute node and rebuild the cluster using that image:

1. Create the cluster as above

2. Log in to one of the compute nodes (see above)

3. Run the following to anonymise the VM:

   ```shell
   sudo service slurmd stop
   sudo systemctl disable slurmd # prevents it coming up on boot before storage etc ready
   sudo vi /etc/hosts # remove openhpc-* hosts, but leave localhost
   sudo rm /etc/slurm/{slurm.conf,reboot.sh} # do NOT delete /etc/slurm/* as need epilog
   sudo rm /var/log/slurm*
   sudo rm /etc/munge/munge.key
   ```

4. In the sausagecloud OpenStack GUI, pick "snapshot" on the above instance, and wait for it to finish saving (may require a refresh of the page).

5. Modify the compute image in `terraform_ohpc/ohpc.tf` to use the above image - **NB** do not change the login image!

6. Delete the cluster and recreate it following the instructions above OR reimage the node(s) as below.


## Reimaging

1. Prepare the new image.
2. Update the compute image name in `terraform_ohpc/openhpc.tf`.
3. From the slurm login node run something like:
    `sudo scontrol reboot ASAP ohpc-compute-[0-2]`
