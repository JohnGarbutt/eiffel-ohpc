#!/usr/bin/env python

import openstack


IMAGE_NAME = "CentOS-7-x86_64-GenericCloud"
FLAVOR_NAME = "C1.vss.tiny"
NETWORK_NAME = "WCDC-Data43"
KEYPAIR_NAME = "usual"


def get_connection():
    # openstack.enable_logging(debug=True)
    conn = openstack.connect()
    return conn

def main():
    conn = get_connection()
    servers = list(conn.list_servers())
    servers = sorted(servers, key = lambda i: i['name'])

    print "[ohpc_login]"
    for server in servers:
        if "login" in server.name:
            ip = server.addresses[server.addresses.keys()[0]][0]['addr']
            print "%s ansible_host=%s ansible_user=centos" % (server.name, ip)

    print "[ohpc_compute]"
    for server in servers:
        if "compute" in server.name:
            ip = server.addresses[server.addresses.keys()[0]][0]['addr']
            print "%s ansible_host=%s ansible_user=centos" % (server.name, ip)

    print """
[cluster_login:children]
ohpc_login

[cluster_control:children]
ohpc_login

[cluster_batch:children]
ohpc_compute"""

if __name__ == '__main__':
    main()
