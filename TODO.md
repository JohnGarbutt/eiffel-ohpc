Things required for a "production" version of this code - these are WON'T-FIX for this proof-of-concept:
- Define min/max nodes required either in ansible or terraform, rather than both.
- Work out split between stackhpc.openhpc role and this repo especially w.r.t. slurm daemon state on compute nodes: The ohpc role (master branch) enables slurmd but this means slurm tries to run jobs on that node - this doesn't work for autoscaling as we need to a) configure filesystems (beegfs role) and b) configure powersaving  scripts (scaling.yml) before this happens.
- Modification of `known_hosts` files by ansible should remove hosts before adding their key - hosts could be added multiple times due to autoscaling which could lead to changed fingerprint issues.
- Messages from resume/suspend.sh and scale.py appear in the wrong order in the powersaving log due to redirection approach.
- This PoC uses /etc/hosts files, using DNS would be cleaner.
- Speed up node creation - currently ~5 minutes even using a snapshot image