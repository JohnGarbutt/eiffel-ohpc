# eiffel-ohpc

[OpenHPC slurm cluster](https://github.com/stackhpc/ansible-role-openhpc) with additional features:
- slurm-driven reimage
- TODO: manual scaling 
- autoscaling

The initial infrastructure creation process is as follows:

```
[ilab-gate] -> [ansible/terraform control host `eiffel-vss-ctl`] --> [slurm control/login node `ohpc-login`]
                                                                  -> [slurm compute node `ohpc-compute-0`]
                                                                  -> [slurm compute node `ohpc-compute-1`]
```

The slurm scheduler can create additional nodes to service the queue, up to a defined maximum number, by calling back to the ansible/terraform control host.

Code and instructions below are for [vss](https://vss.cloud.private.cam.ac.uk/) but other OpenStack clouds will be similar.

## Creating the ansible/terraform control host `eiffel-vss-ctl` and associated infrastructure

From the [vss web dashboard](https://vss.cloud.private.cam.ac.uk/), from Project / Compute / Access & Security / API Access download an OpenStack RC File **V3**. Upload that to ilab-gate.

On `ilab-gate`:
- If you want to be able to log into the control host from your local machine, copy the public keyfile you want to use onto `ilab-gate` , e.g. to `~/.ssh/id_rsa_mykeypair.pub`.
- Clone this repo and checkout branch `vss`.
- Now deploy the ansible/terraform control host `eiffel-vss-ctl` and infrastructure using terraform:

  ```shell
  source ~/vss-openrc-v3.sh # will prompt for password
  cd /ilab-home/$USER/eiffel-ohpc/terraform_ctl
  terraform init
  terraform apply -var ssh_key_file=~/.ssh/id_rsa_mykeypair # **NB** note no .pub extension
  ```
- From the machine with the private key for `mykeypair`, log into ansible/terraform control host `eiffel-vss-ctl` using the IP it outputs as user `centos`.

On the ansible/tf control host `eiffel-vss-ctl`:

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

- Install terraform on $PATH (NB the autoscaling scripts need to be able to run this without a shell, so put it in /bin rather than adding it to ~/bin or modifying .bashrc etc):

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

- Modify `group_vars/all.yml` for:
  - `min_nodes` is the minimum number of nodes / number of persistent nodes you want
  - `max_nodes` is the max number of nodes the cluster can have
  - `control_host_ip` is the public IP for the ansible/terraform control host `eiffel-vss-ctl` 

- If required, modify  `~/eiffel-ohpc/terraform_ohpc/openhpc.tf` so that:
    - `keypair` is the name of the keypair created on the ansible/tf control host - **NB:** NOT the keypair used to login 
      to the ansible/tf control host - agent forwarding will not work with this autoscaling setup
    
- Add `172.24.44.2 vss.cloud.private.cam.ac.uk` to `/etc/hosts`. FIXME:

## Creating the slurm cluster

On the ansible/tf control host:

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

Note that due to the way ssh keys are deployed in the above, all logins to cluster nodes have to go through the ansible/tf control host despite the slurm control node having a public IP. For production use this would be easy to change but it is convenient for development anyway as that is where the git repo is.

For the slurm control/login node just go through the ansible/tf control host first, e.g.:

```shell
ssh centos@<ansible/tf control host IP>
ssh centos@<ohpc-login IP>
```

To login to compute nodes (e.g. for debugging) go from the ansible/tf control host but then proxy through the slurm head node, e.g.:

```shell
ssh centos@<ansible/tf control host IP>
ssh -o ProxyCommand="ssh centos@<ohpc-login IP> -W %h:%p" <ohpc-compute-N IP>
```

## Restarting slurm control daemon
If slurm gets confused about node/job state e.g. during autoscaling development, from the slurm control/login node:

```shell
sudo service slurmctld stop # stop daemon
top -u slurm -n 1 # check it's stopped
sudo /sbin/slurmctld -c # -c forces it to ignore any partition/job state files - all jobs will be lost
```

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

## Testing

The cluster has an NFS-shared directory at /mnt/ohpc (exported from the slurm control/login node).

A basic MPI "hello world" program can be installed by logging into the slurm control node and running:

```shell
sudo yum install -y git
cd /mnt/ohpc
sudo install -d centos -o centos
cd centos
git clone https://github.com/stackhpc/hpc-tests
cd hpc-tests/helloworld/
module load gnu7 openmpi3
mpicc -o helloworld helloworld.c
```

To run e.g. on the 2 existing nodes (-N) with total of 2 processes (-n) run:

```shell
sbatch -N 2 -n 2 runhello
```

## Autoscaling
If more than 2 nodes are required the cluster will autoscale up - this will take some time (~2-3 minutes with a snapshot image, 8+ minutes with a ), with the job showing as "Configuring/CF" state until ready. It will then autoscale down almost immediately (see under "AUTOSCALING" in `slurm.conf` for relevant timing parameters).

The autoscaling machinery repurposes slurm's power management features to add/remove nodes as required. The 2 persistent compute nodes (i.e. below `min_nodes`) in the cluster are defined in `slurm.conf` and instantiated at cluster deployment as usual. Compute nodes between `min_nodes` and `max_nodes` are not instatiated when the cluster is deployed but are still defined the in `slurm.conf`, with "State=CLOUD". This is a slurm-defined state which tells slurm it contact these nodes initially. They will not appear in e.g. `sinfo` output until jobs have been scheduled on them. Note that slurm still assumes a 1:1 mapping between compute nodes and instances - all nodes must be defined in `slurm.conf`. This has some consequences which are discussed below.

The autoscaling mechanism is that:
- The slurm scheduler decides more nodes are needed and calls `/etc/slurm/resume.sh` (created from the template `eiffel-ohpc/slurmscripts/resume.j2`, configured by `slurm.conf:ResumeProgram`) on the slurm control node, as user `slurm` (`slurm.conf:SlurmUser`), with a "hostlist expression" defining the additional nodes required e.g. "ohpc-compute-[3-4,8]".
- This uses `scontrol` to expand the hostlist expression into individual hosts, then ssh's back into the ansible/terraform control host and runs `eiffel-ohpc/slurmscripts/scale.py` (created from the template `<same>.j2`) as the user who deployed the cluster, passing it the list of new nodes required.
- This essentially runs terraform to create instances and ansible to configure them, although there a few complications to this discussed below.
- The last step of the ansible-driven configuration is to start the `slurmd` on each new node. This then contacts the `slurmctdl` on the slurm control node, which informs it that the node is ready, and the
  job is started on the node.

Once the scheduler has decided nodes are no longer required (again see autoscaling parameters) a similar process happens using `suspend.sh` on the slurm control node to run `scale.py` with a list of nodes to
remove.

In a production environment it may be preferable to use a persistent service (e.g Rundeck) rather than ssh'ing back into the ansible/terraform control host to run scripts. However it is considered very strongly desirable that both deployment and autoscaling use the same repo to avoid problems encountered with approaches which define these configurations separately.

The interaction of `scale.py` with ansible/terraform needs some discussion and will still be relevant even with a persistent service.

Firstly, note that in contrast to the assumptions in the basic openhpc role, the cluster's compute nodes may no longer be contigous due to nodes being added/removed out of sequence by the scheduler. This, and flexibility in which nodes are instantiated, are handled in `eiffel-ohpc/terraform_ohpc/openhpc.tf` by defining the compute nodes using a local set variable (`nodeset`) which is populated at initial deploy from `min_nodes` and at later runs from a command-line variable `nodenames` giving a list of compute host hostnames which should exist in the cluster. Since this is all compute nodes, not just the additional nodes, `scale.py` construct this list by querying terraform for the currently-instantiated nodes and adding this to the additional nodes.

Secondly, some additonal complication is introduced because hostname/IP lookups are defined using `/etc/hosts` on each node, populated by ansible using inventory information generated by terraform. This means that on scale-up at least, the ansible has to be run on *all* nodes in the cluster to refresh this information. On scale-down stale info in `/etc/hosts` is assumed to be acceptable, as slurm will not try to communicate with 'suspended' nodes anyway.

If autoscaling was the only required feature the above would be sufficent, and `scale.py` could simply:
- run terraform passing the list of all nodes required in the cluster
- run ansible on all nodes

However this assumes that the terraform describes the state of all nodes in the cluster. This assumption is broken by the reimage automation described below; in that case only part of the cluster may have been reimaged (e.g. due to running jobs on some nodes). If terraform is run on all nodes in that state, it will discover a discrepancy between the "desired", reimaged state and the current running state of some nodes, and would therefore delete and recreate them, killing any jobs on them. Therefore as well as passing the list of all nodes to terraform in the `nodenames` command-line option, multiple `-target` options are used on the terraform command to restrict it to only modifying the nodes specified by slurm (i.e. nodes to add on upscale or remove on downscale).

Additional details of slurm's functionality, including configuration parameters which may needed in production, are given in:
- https://slurm.schedmd.com/elastic_computing.html
- https://slurm.schedmd.com/power_save.html

## Reimaging
To change the image used by compute nodes:

1. Prepare the new image and upload to `vss`.
2. Update the compute image name in `terraform_ohpc/openhpc.tf`.
3. From the slurm login node run something like:
    `sudo scontrol reboot ASAP ohpc-compute-[0-10]`

Nodes will be drained, then recreated with a new image.

TODO: describe how this works.

## Manual size changes
To manually change the size (number of persistent nodes) of the cluster:

1. Change `min_nodes` in `group_vars/all.yml`
2. Run `ansible-playbook -i terraform_ohpc/ohpc_hosts resize.yml`

If scaling down, the appropriate number of nodes will be drained starting from the highest-numbered nodes. By default, it waits up to 1 day for the drain to complete.

**NB: This currently only works for clusters with no cloud nodes and a single partition.**

TODO: describe how this works.

## Image pipeline decisions
All nodes only require a "plain" centos image - ansible will install all necessary packages and set all necessary configuration on this. However as discussed above a snapshot image may be useful to signficantly
speed up creation of new nodes.

In production, it may be considered desirable to prebuild images in a separate pipeline e.g. to allow off-line testing. This would allow (but not require) potentially nearly all of the ansible to be removed. It is suggested that at a minimum the ansible would need to:
- template out /etc/slurm/slurm.conf (`stackhpc.openhpc` role)
- copy ssh keys (scaling.yml, reimage.yml) - if the current ssh + scripts approach is used for rescaling/reimage
- start slurm daemons (`stackhpc.openhpc` role)

Note that it is assumed that a production cluster would have DNS hence the templating out of /etc/hosts (currently in the `stackhpc.openhpc` role) would not be required.

## Log locations

- slurm control daemon - `ohpc-login`:/var/log/slurmctld.log
- autoscaling - `ohpc-login`:/var/tmp/slurmpwr.log
- reimaging - `eiffel-vss-ctl`:/var/tmp/reimage.log

# Known Issues
- Messages in autoscaling/reimaging logs from the different hosts involved don't appear in running order.
- TODO: rescaling problem