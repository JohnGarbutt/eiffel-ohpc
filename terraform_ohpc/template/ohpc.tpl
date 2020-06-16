[all:vars]
ansible_user=centos
ansible_ssh_common_args='-C -o ControlMaster=auto -o ControlPersist=60s -o ProxyCommand="ssh centos@${fip} -W %h:%p"'
ohpc_proxy_address=${fip}
control_host=${control_host}

[ohpc_login]
${login}
[ohpc_compute]${computes}
[cluster_login:children]
ohpc_login

[cluster_control:children]
ohpc_login

[cluster_batch:children]
ohpc_compute

[jg_login:children]
ohpc_login

[jg_compute:children]
ohpc_compute
