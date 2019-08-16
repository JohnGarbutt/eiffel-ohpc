[ohpc_login]
${login}
[ohpc_compute]${computes}
[cluster_login:children]
ohpc_login

[cluster_control:children]
ohpc_login

[cluster_batch:children]
ohpc_compute

[cluster_beegfs_mgmt:children]
ohpc_login

[cluster_beegfs_mds:children]
ohpc_login

[cluster_beegfs_oss:children]
ohpc_compute

[cluster_beegfs_client:children]
ohpc_login
ohpc_compute
