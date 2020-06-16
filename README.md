# eiffel-ohpc

An [OpenHPC slurm](https://github.com/stackhpc/ansible-role-openhpc) cluster with additional features:
- slurm-controlled reimage of compute nodes
- manual resizing of cluster
- automatic resizing of cluster driven by slurm ("autoscaling")

The cluster has:
- An NFS share at `/mnt/ohpc` exported from the slurm control/login node
- A minimum of 2 and a maximum of 4 compute nodes - this can be changed via configuration
- No users defined other than the default `centos` user
- A single slurm partition

Code in this branch and the instructions below are for [vss](https://vss.cloud.private.cam.ac.uk/) but other OpenStack clouds will be similar.

The initial infrastructure creation process is as follows:

```
[ilab-gate] -> [ansible/terraform control host 'eiffel-vss-ctl'] --> [slurm control/login node 'ohpc-login']
                                                                  -> [slurm compute node 'ohpc-compute-0']
                                                                  -> [slurm compute node 'ohpc-compute-1']
```

## Creating the ansible/terraform control host `eiffel-vss-ctl` and associated infrastructure

From the [vss web dashboard](https://vss.cloud.private.cam.ac.uk/), from Project / Compute / Access & Security / API Access download an OpenStack RC File **V3**. Upload that to ilab-gate.

On `ilab-gate`:
- If you want to be able to log into the ansible/terraform control host from your local machine, copy the public keyfile you want to use onto `ilab-gate` , e.g. to `~/.ssh/id_rsa_mykeypair.pub`.
- Clone this repo and checkout branch `vss`.
- Now deploy the ansible/terraform control host `eiffel-vss-ctl` and infrastructure using terraform:

  ```shell
  source ~/vss-openrc-v3.sh # will prompt for password
  cd /ilab-home/$USER/eiffel-ohpc/terraform_ctl
  terraform init
  terraform apply -var ssh_key_file=~/.ssh/id_rsa_mykeypair # **NB** note no .pub extension
  ```
- From the machine with the private key for `mykeypair`, log into the ansible/terraform control host `eiffel-vss-ctl` as user `centos`using the IP it outputs .

On the ansible/tf control host `eiffel-vss-ctl`:

- Install wget, git, unzip, pip (via epel) and virtualenv:

  ```shell
  sudo yum install -y wget git unzip
  sudo yum install -y python3-pip libselinux-python3
  sudo pip3 install -U pip # update pip
  sudo pip3 install virtualenv
  ```

- Generate some entropy (else eventually everything stalls):

  ```shell
  sudo yum install -y rng-tools
  sudo systemctl start rngd
  sleep 5 # wait for a bit for start ...
  cat /proc/sys/kernel/random/entropy_avail # should be > 200
  ```

  Clone this repo and checkout the **vss** branch - this is the repo which will be used to build the actual cluster:

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
  wget https://releases.hashicorp.com/terraform/0.12.26/terraform_0.12.26_linux_amd64.zip
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
    
- Add `172.24.44.2 vss.cloud.private.cam.ac.uk` to `/etc/hosts`.

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

For IP addresses see the ansible inventory at `terraform_ohpc/ohpc_hosts`.

## Restarting slurm control daemon
If slurm gets confused about node/job state e.g. during development/debugging, from the slurm control/login node run:

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

5. Modify the compute image name in `group_vars/all.yml` to use the above image.

6. Delete the cluster and recreate it following the instructions above OR reimage the node(s) as below.

## Testing

Basic MPI "hello world" programs can be installed for testing by running:

    ansible-playbook -i terraform_ohpc/ohpc_hosts test.yml

This creates binaries `helloworld` and `helloworld-forever.c` in the NFS share at `/mnt/ohpc/centos/hpc-tests/helloworld`.

To run this on 2 nodes (-N) with a total of 2 processes (-n) use e.g.:

    sbatch -N 2 -n 2 runhello

The output in `slurm-*.out` should show reports from one process on each node.

## Autoscaling
If `group_vars/all.yml` has `max_nodes` > `min_nodes` the cluster can autoscale up if required to service the queue. This will take some time (~2-3 minutes with a snapshot image, ~8+ minutes with a plain centos image), with the job showing as "Configuring/CF" state until ready. It will then autoscale down almost immediately (see under "AUTOSCALING" in `slurm.conf` for relevant timing parameters - values are currently set for testing and are not appropriate for production).

The autoscaling machinery repurposes slurm's power management features to add/remove nodes as required. The persistent
compute nodes (i.e. below `min_nodes`) in the cluster are defined in `slurm.conf` and instantiated at cluster deployment as usual. Compute nodes between `min_nodes` and `max_nodes` are not instatiated when the cluster is deployed but are still defined the in `slurm.conf`, with "State=CLOUD". This is a slurm-defined state which tells slurm it cannot contact these nodes initially. They will not appear in e.g. `sinfo` output until jobs have been scheduled on them. Note that slurm still assumes a 1:1 mapping between compute nodes and instances, i.e. all nodes must be defined in `slurm.conf`. This has some consequences which are discussed below.

The autoscaling mechanism is that:
- The slurm scheduler decides more nodes are needed and calls `/etc/slurm/resume.sh` (created from the template `eiffel-ohpc/slurmscripts/resume.j2`, configured by `slurm.conf:ResumeProgram`) on the slurm control node, as user `slurm` (`slurm.conf:SlurmUser`), with a "hostlist expression" defining the additional nodes required e.g. "ohpc-compute-[3-4,8]".
- This uses `scontrol` to expand the hostlist expression into individual hosts, then ssh's back into the ansible/terraform control host and runs `eiffel-ohpc/slurmscripts/reconfigure.py` (created from the template `<same>.j2`) as the user who deployed the cluster, passing it the mode "resume" and the list of new nodes required.
- This essentially runs terraform to create instances and ansible to configure them, although there a few complications to this discussed below.
- It then runs the same ansible used to deploy the cluster, with the last step of this being to start the `slurmd` on each new node. This then contacts the `slurmctdl` on the slurm control node, which informs it that the node is ready, and the job is started on the node.

Once the scheduler has decided nodes are no longer required (again see autoscaling parameters) a similar process happens using `suspend.sh` on the slurm control node to run `reconfigure.py` in "suspend" mode with a list of nodes to remove.

In a production environment it may be preferable to use a persistent service (e.g Rundeck) rather than ssh'ing back into the ansible/terraform control host to run scripts - the approach used here was chosen as it does not require any additional tooling which allows the underlying aspects to be more easily understood. Whatever approach is used it is considered strongly desirable that both deployment and autoscaling use the same repo to avoid problems encountered with approaches which define the two configurations separately.

The interaction of the `reconfigure.py` script with ansible/terraform needs some discussion which is likely to be still relevant even if the ssh/script-driven approach is replaced with a persistent service.

Firstly, note that in contrast to the assumptions in the basic stackhpc.openhpc role, the cluster's compute nodes may no longer be contigous due to nodes being added/removed out of sequence by the scheduler. This, and flexibility in which nodes are instantiated, are handled in the the terraform configuration (`eiffel-ohpc/terraform_ohpc/openhpc.tf`) by defining the compute node names as a set (`nodeset`) which is generated for the initial deployment from `min_nodes` and directly set in later autoscale runs from a variable (`nodenames`) set on the command-line with specific hostnames. Note that this set must define *all* compute node names, not just the changes, as terraform requires the total cluster state to create the inventory for ansible. The `reconfigure.py` script constructs this total list by querying terraform for the list of currently-instantiated compute nodes and combining it with the additonal nodes it has been asked for.

Secondly, some additonal complication is introduced because hostname/IP lookups are defined using `/etc/hosts` on each node, populated by ansible using inventory information generated by terraform. This means that on scale-up at least, the ansible has to be run on *all* nodes in the cluster to refresh this information. On scale-down leaving stale info in `/etc/hosts` is assumed to be acceptable, as slurm will not try to communicate with nodes it has 'suspended'.

If autoscaling was the only required feature the above would be sufficent, and for autoscaling `reconfigure.py` could simply:
- run terraform passing the list of all nodes required in the cluster
- run ansible on all nodes

However this assumes that the terraform describes the state of all nodes in the cluster. This assumption is broken by the reimage automation described below; in that case only part of the cluster may have been reimaged (e.g. due to running jobs on some nodes). If terraform is run on all nodes in that state, it will discover a discrepancy between the "desired" state in the config (i.e. with the new image) and the current state of all nodes, and would therefore delete and recreate all nodes. This would clearly terminate all slurm jobs. Therefore as well as passing the list of all nodes to terraform in the `nodenames` command-line option, multiple `-target` options are passed to the terraform command to restrict it to only modifying the nodes specified by slurm (i.e. nodes to add on upscale or remove on downscale).

Lastly, note that the autoscaling does not run `scontrol reconfigure` or restart the slurm daemons; as the slurm configuration remains the same throughout there is no need to, so the scheduling loop will not be interrupted by autoscaling.

Additional details of slurm's functionality, including configuration parameters which may needed in production, are given in:
- https://slurm.schedmd.com/elastic_computing.html
- https://slurm.schedmd.com/power_save.html

## Reimaging
To change the image used by compute nodes:

1. Prepare the new image and upload to `vss`.
2. Update the compute image name in `group_vars/all.yml`.
3. From the slurm login node run something like:
    `sudo scontrol reboot ASAP ohpc-compute-[0-1]`

Nodes will be drained, then recreated with a new image.

The reimaging mechanism is that:
- The relevant node(s) is drained and then `/etc/slurm/reboot.sh` (created from the template `slurmscripts/reboot.j2`, configured by `slurm.conf:RebootProgram`) is called on that compute node.
- This ssh's back into the ansible/terraform control host and runs `eiffel-ohpc/slurmscripts/reconfigure.py` (created from the template `<same>.j2`) as the user who deployed the cluster, passing it the mode "update" and its own hostname. This:
  - Runs terraform targeted just at this node; terraform notices that the required image is not the same as the current image, so deletes and recreates the node with the new image.
  - Runs ansible to configure all nodes; this installs and configures slurm on the recreated node and also updates `/etc/hosts` across the cluster - with DNS available the ansible could be limited to only the changed node.
  Note these are actually the same actions as for the "resume" mode; the differences being that for reboot:
  - the set of compute host names is unchanged
  - the terraform is targeted at only a single instance, because this script is run by the compute node's slurmd, rather than the slurm control node's slurmctdl for autoscaling.

As discussed above the requirement for reimaging drives requirement to limit terraform to specific nodes, as otherwise an autoscale occuring after step 2. above would result in all compute nodes being deleted and recreated, killing jobs.

NB: This approach actually has broader functionality than only reimaging; any changes to the terraform instance definition (e.g. instance type) will be applied to the drained/rebooted node(s) and any change to the ansible (e.g. software versions) would be applied to all nodes.

A potential enhancement would be for `reboot.sh` select between either an actual reboot or a reimage/update, depending on the "Reason" field in the slurm state for this node.

## Manual size changes
To manually change the size (number of persistent nodes) of the cluster:

1. Change `min_nodes` in `group_vars/all.yml`
2. Run `ansible-playbook -i terraform_ohpc/ohpc_hosts resize.yml`

If scaling down, the appropriate number of nodes will be drained starting from the highest-numbered nodes. The scale-down proceeds as soon as all nodes have been drained (by default waiting up to 1 day for this to complete).

**NB: This currently only works for clusters with no cloud nodes and a single partition.**

The manual size change mechanism is:
- `resize.yml` compares the inventory against the current `min_nodes` value to construct a list of nodes to add or remove.
- If deleting nodes:
  - These are drained
  - `reconfigure.py` is called in `delete` mode which:
    - Runs terraform to remove the nodes and update the inventory
    - Runs ansible on all nodes: this is required in order to update slurm.conf as well as /etc/hosts
    
    Note that the 2nd of these was not required for the `suspend` mode used for autoscale where the slurm.conf is not changed.

- If adding nodes:
  - `reconfigure.py` is called in `resume` mode - see description above.
- In both cases the slurm daemons are then restarted. This rereads the configuration, but does not lose job state.

## Image creation options
All nodes only require a "plain" centos image - ansible will install all necessary packages and set all necessary configuration on this. However as discussed above a snapshot image may be useful to signficantly speed up creation of new nodes.

In production, it may be considered desirable to prebuild images in a separate pipeline e.g. to allow off-line testing. This would allow (but not require) potentially nearly all of the ansible to be removed. It is suggested that at a minimum the ansible would need to:
- template out /etc/slurm/slurm.conf (`stackhpc.openhpc` role)
- copy ssh keys (scaling.yml, reimage.yml) - if the current ssh + scripts approach is used for rescaling/reimage
- start slurm daemons (`stackhpc.openhpc` role)

The above assumes that a production cluster would have DNS hence the templating out of /etc/hosts would not be required.

## Log locations

- slurm control daemon - `ohpc-login`:/var/log/slurmctld.log
- autoscaling - `ohpc-login`:/var/tmp/slurmpwr.log
- reimaging - `eiffel-vss-ctl`:/var/tmp/reimage.log

## Known Issues & Rough Edges
- Messages in the autoscaling/reimaging logs from scripts on different hosts don't appear in running order.
- On the 2nd and subsequent autoscaling the slurmctld loses contact with one of the autoscaled nodes during the job completion step. See [issue #4](https://github.com/stackhpc/eiffel-ohpc/issues/4) although note that the job does run, produce output and eventually complete.
- If the image isn't changed, then the "reboot" functionality doesn't actually perform a reboot which is confusing.
- Currently only a single partition is supported by the manual scaling code.

## Design

The table below shows the actions required for each required functionality:

- initial deployment
- autoscaling: resume, suspend
- manual size changes: enlarge, shrink
- reimaging: update

The table also shows where the action is initiated from and which steps (marked "tf") use terraform.

| step                              | deploy | resume    | suspend   | enlarge | shrink | update |
| --------------------------------- | ------ | --------- | --------- | ------- | ------ | ------ |
|                    INITIATOR -->  | USER   | SLURMCTLD | SLURMCTLD | USER    | USER   | SLURMD |
| drain instances                   |        |           |           |         | Y      | Y      |
| wait for all drained              |        |           |           |         | Y      | Y      |
| delete instances  (tf)            |        |           | Y         |         | Y      | Y      |
| create instances  (tf)            | Y      | Y         |           | Y       |        | Y      |
| refresh inventory (tf)            | Y      | Y         | Y         | Y       | Y      | Y      |
| (re)write /etc/hosts              | ALL    | ALL       | ALL       | ALL     | ALL    | ALL    |
| install s/w, configure shares etc | Y      | Y         |           | Y       |        | Y      |
| create slurm.conf                 | ALL    | Y         |           | Y       |        | Y      |
| modify slurm.conf                 |        |           |           | ALL     | ALL    |        |
| start/restart slurm daemons       | ALL    | Y         |           | ALL     | ALL    | Y      |

