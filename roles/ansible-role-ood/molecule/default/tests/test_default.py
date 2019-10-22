import os
import sys
import pytest
import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ["MOLECULE_INVENTORY_FILE"]
).get_hosts("all")

try:
    # setup cluster_name variable
    os.environ["CLUSTER_NAME"]
    CLUSTER_NAME = os.environ["CLUSTER_NAME"]
except:
    print("Please set the environment variable CLUSTER_NAME")
    sys.exit(1)

try:
    # setup host_regex variable
    os.environ["HOST_REGEX"]
    HOST_REGEX = os.environ["HOST_REGEX"]
except:
    print("Please set the environment variable HOST_REGEX")
    sys.exit(1)


def test_ondemand_is_installed(host):
    ondemand = host.package("ondemand")
    assert ondemand.is_installed


def test_nc_is_installed(host):
    netstat = host.package("nc")
    assert netstat.is_installed


def test_clusterd_exists(host):
    clusterd = host.file("/etc/ood/config/clusters.d")
    assert clusterd.is_directory


def cluster_config_deployed(host):
    config = host.file(f"/etc/ood/config/clusters.d/{CLUSTER_NAME}.yml")
    assert config.exists


def check_desktop_settings(host):
    desktop_settings = host.file("/etc/ood/config/apps/desktop")
    assert desktop_settings.is_directory


def interactive_script(host):
    submission_script = host.file("/etc/ood/config/apps/desktop/submit/submit.yml.erb")
    assert submission_script.exists


def old_uids(host):
    uids = host.file("/etc/ood/config/nginx_stage.yml")
    assert uids.contains("min_uid: 500")


def check_reverse_proxy(host):
    proxy = host.file("/etc/ood/config/ood_portal.yml")
    assert proxy.contains("node_uri: '/node'")
    assert proxy.contains("rnode_uri: '/rnode'")
    assert proxy.contains(f"host_regex: {HOST_REGEX}")


def httpd24_running(host):
    httpd24_daemon = "httpd24-httpd"
    httpd = host.service(httpd24_daemon)
    assert httpd.is_enabled
    assert httpd.is_running


# def test_firewalld_running_and_enabled(host):
#     firewalld_daemon = "firewalld"
#     print(host.system_info.distribution)
#     print(firewalld_daemon)
#     firewalld = host.service(firewalld_daemon)

#     assert firewalld.is_running
#     assert firewalld.is_enabled

#Checks to make sure that the novnc bits have worked correctly

@pytest.mark.parametrize("name,text", [
    ("rfb.js", "clipboardPasteFrom: function"),
    ("ui.js", "openClipboardPanel: function"),
    # ("app.V1.js",""),
    # ("vnc.html", ""),
])
def novnc_copy_removed(host, name, text):
    filename = host.file(name) 
    assert not filename.contains(text)

def test_port_80_listening(host):
    port80 = host.socket("tcp://0.0.0.0:80")
    assert port80.is_listening


def test_port_443_listening(host):
    port443 = host.socket("tcp://0.0.0.0:443")
    assert port443.is_listening
