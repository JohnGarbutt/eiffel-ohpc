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
    print "[openhpc_login]"
    print "TODO: add login here"
    print "[openhpc_compute]"

    for server in conn.compute.list_servers()
        ip = server.addresses[server.addresses.keys()[0]][0]['addr']
        print "%s ansible_host=%s ansible_user=centos" % (server.name, ip)

    print """
[cluster_login:children]
openhpc_login

[cluster_control:children]
openhpc_login

[cluster_batch:children]
openhpc_compute"""

if __name__ == '__main__':
    main()
