

########################################################
#Modify the network part
########################################################
DNS_SERVER=${DNS_SERVER:-"166.111.8.28"}

#CONTROLLER_EXT_ETH=${CONTROLLER_EXT_ETH:-"eth0"}
CONTROLLER_EXT_IP=${CONTROLLER_EXT_IP:-"10.10.0.200"}
#CONTROLLER_EXT_GW=${CONTROLLER_EXT_IP:-"10.10.0.1"}

CONTROLLER_MNG_ETH=${CONTROLLER_EXT_ETH:-"eth2"}
CONTROLLER_MNG_IP=${CONTROLLER_EXT_IP:-"192.168.10.51"}



#For Exposing OpenStack API over the internet
#auto $CONTROLLER_EXT_ETH
#iface $CONTROLLER_EXT_ETH inet static
#address $CONTROLLER_EXT_IP
#netmask 255.255.255.0
#gateway $CONTROLLER_EXT_GW
#dns-nameservers $DNS_SERVER


#for future modification
#auto eth0
#iface eth0 inet dhcp

cat <<EOF >> /etc/network/interfaces

#Not internet connected(used for OpenStack management)
auto $CONTROLLER_MNG_ETH
iface $CONTROLLER_MNG_ETH inet static
address $CONTROLLER_MNG_IP
netmask 255.255.255.0
EOF

/etc/init.d/networking restart


####################################################
#MySQL & RabbitMQ
####################################################
apt-get install debconf debconf-utils


###############???????????????????to be tested.........
MYSQL_PASSWD=${MYSQL_PASSWD:-"root"}
cat <<MYSQL_PRESEED | debconf-set-selections  
mysql-server-5.5 mysql-server/root_password password $MYSQL_PASSWD  
mysql-server-5.5 mysql-server/root_password_again password $MYSQL_PASSWD  
mysql-server-5.5 mysql-server/start_on_boot boolean true  
MYSQL_PRESEED

apt-get install -y --no-install-recommends mysql-server python-mysqldb
###############???????????????????to be tested.........

sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/my.cnf
service mysql restart
apt-get install -y rabbitmq-server


####################################################
#Node synchronization
####################################################
apt-get install -y ntp
sed -i 's/server ntp.ubuntu.com/server ntp.ubuntu.com\nserver 127.127.1.0\nfudge 127.127.1.0 stratum 10/g' /etc/ntp.conf
service ntp restart

####################################################
#Other Service & Configurations
####################################################
apt-get install -y vlan bridge-utils
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
# To save you from rebooting, perform the following
sysctl net.ipv4.ip_forward=1

####################################################
#Keystone
####################################################
apt-get install -y keystone
mysql -u root -p"root"
CREATE DATABASE keystone;
GRANT ALL ON keystone.* TO 'keystoneUser'@'%' IDENTIFIED BY 'keystonePass';
quit;


##########?????????????????????????????????????????????????/How to combine ? with #
CONTROLLER_MNG_IP=${CONTROLLER_EXT_IP:-"192.168.10.51"}
#
#sed -i 's#connection = sqlite:////var/lib/keystone/keystone.db#connection = mysql://keystoneUser:keystonePass@$CONTROLLER_MNG_IP/keystone#g' /etc/keystone/keystone.conf 
######################???????????????????????????????
service keystone restart
keystone-manage db_sync



#Modify the HOST_IP and HOST_IP_EXT variables before executing the scripts

chmod +x keystone_basic.sh
chmod +x keystone_endpoints_basic.sh

./keystone_basic.sh
./keystone_endpoints_basic.sh
####################################Modify the IP address

##################################
#a simple credential file
##################################

CONTROLLER_EXT_IP=${CONTROLLER_EXT_IP:-"10.10.0.200"}
cat <<EOF >creds
export OS_TENANT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=admin_pass
export OS_AUTH_URL="http://$CONTROLLER_EXT_IP:5000/v2.0/"
EOF
source creds

echo "source ~/creds" >>~/.bashrc

##################################
#To test Keystone, curl request
##################################
CONTROLLER_EXT_IP=${CONTROLLER_EXT_IP:-"10.10.0.200"}
apt-get install -y curl openssl
curl http://$CONTROLLER_EXT_IP:35357/v2.0/endpoints -H 'x-auth-token: ADMIN'

####################################################
#Glance
####################################################
apt-get install -y glance
mysql -u"root" -p"root"
CREATE DATABASE glance;
GRANT ALL ON glance.* TO 'glanceUser'@'%' IDENTIFIED BY 'glancePass';
quit;

#############????????????????????????????????????????????????????
/etc/glance/glance-api-paste.ini
CONTROLLER_MNG_IP=${CONTROLLER_EXT_IP:-"192.168.10.51"}
[filter:authtoken]
paste.filter_factory = keystone.middleware.auth_token:filter_factory
auth_host = $CONTROLLER_MNG_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = glance
admin_password = service_pass


/etc/glance/glance-registry-paste.ini 
[filter:authtoken]
paste.filter_factory = keystone.middleware.auth_token:filter_factory
auth_host = $CONTROLLER_MNG_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = glance
admin_password = service_pass

/etc/glance/glance-api.conf
sql_connection = mysql://glanceUser:glancePass@$CONTROLLER_MNG_IP/glance

[paste_deploy]
flavor = keystone

/etc/glance/glance-registry.conf
sql_connection = mysql://glanceUser:glancePass@$CONTROLLER_MNG_IP/glance

[paste_deploy]
flavor = keystone

service glance-api restart; service glance-registry restart
glance-manage db_sync
service glance-api restart; service glance-registry restart

##################################
#Mk images and test
##################################
mkdir images
cd images
wget https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img
glance image-create --name myFirstImage --is-public true --container-format bare --disk-format qcow2 < cirros-0.3.0-x86_64-disk.img
glance image-list

####################################################
#Quantum
####################################################
apt-get install -y quantum-server quantum-plugin-openvswitch

mysql -u root -p"root"
CREATE DATABASE quantum;
GRANT ALL ON quantum.* TO 'quantumUser'@'%' IDENTIFIED BY 'quantumPass';
quit;

CONTROLLER_MNG_IP=${CONTROLLER_EXT_IP:-"192.168.10.51"}
/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini
#Under the database section
[DATABASE]
sql_connection = mysql://quantumUser:quantumPass@$CONTROLLER_MNG_IP/quantum

#Under the OVS section
[OVS]
tenant_network_type=vlan
network_vlan_ranges = physnet1:1:4094

/etc/quantum/api-paste.ini

[filter:authtoken]
paste.filter_factory = keystone.middleware.auth_token:filter_factory
auth_host = $CONTROLLER_MNG_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = quantum
admin_password = service_pass

service quantum-server restart


####################################################
#Nova
####################################################
apt-get install -y nova-api nova-cert novnc nova-consoleauth nova-scheduler nova-novncproxy

mysql -u root -p"root"
CREATE DATABASE nova;
GRANT ALL ON nova.* TO 'novaUser'@'%' IDENTIFIED BY 'novaPass';
quit;

/etc/nova/api-paste.ini
[filter:authtoken]
paste.filter_factory = keystone.middleware.auth_token:filter_factory
auth_host = $CONTROLLER_MNG_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = nova
admin_password = service_pass
signing_dirname = /tmp/keystone-signing-nova


/etc/nova/nova.conf
[DEFAULT]
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/run/lock/nova
verbose=True
api_paste_config=/etc/nova/api-paste.ini
scheduler_driver=nova.scheduler.simple.SimpleScheduler
s3_host=$CONTROLLER_MNG_IP
ec2_host=$CONTROLLER_MNG_IP
ec2_dmz_host=$CONTROLLER_MNG_IP
rabbit_host=$CONTROLLER_MNG_IP
dmz_cidr=169.254.169.254/32
metadata_host=$CONTROLLER_MNG_IP
metadata_listen=0.0.0.0
sql_connection=mysql://novaUser:novaPass@$CONTROLLER_MNG_IP/nova
root_helper=sudo nova-rootwrap /etc/nova/rootwrap.conf

# Auth
auth_strategy=keystone
keystone_ec2_url=http://$CONTROLLER_MNG_IP:5000/v2.0/ec2tokens
# Imaging service
glance_api_servers=$CONTROLLER_MNG_IP:9292
image_service=nova.image.glance.GlanceImageService

# Vnc configuration
vnc_enabled=true
novncproxy_base_url=http://$CONTROLLER_EXT_IP:6080/vnc_auto.html
novncproxy_port=6080
vncserver_proxyclient_address=$CONTROLLER_EXT_IP
vncserver_listen=0.0.0.0

# Network settings
network_api_class=nova.network.quantumv2.api.API
quantum_url=http://$CONTROLLER_MNG_IP:9696
quantum_auth_strategy=keystone
quantum_admin_tenant_name=service
quantum_admin_username=quantum
quantum_admin_password=service_pass
quantum_admin_auth_url=http://$CONTROLLER_MNG_IP:35357/v2.0
libvirt_vif_driver=nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver=nova.virt.libvirt.firewall.IptablesFirewallDriver

# Compute #
compute_driver=libvirt.LibvirtDriver

# Cinder #
volume_api_class=nova.volume.cinder.API
osapi_volume_listen_port=5900



####################################################
#Cinder
####################################################
apt-get install -y cinder-api cinder-scheduler cinder-volume iscsitarget open-iscsi iscsitarget-dkms

sed -i 's/false/true/g' /etc/default/iscsitarget
service iscsitarget start
service open-iscsi start

mysql -u"root" -p"root"
CREATE DATABASE cinder;
GRANT ALL ON cinder.* TO 'cinderUser'@'%' IDENTIFIED BY 'cinderPass';
quit;



/etc/cinder/api-paste.ini
[filter:authtoken]
paste.filter_factory = keystone.middleware.auth_token:filter_factory
service_protocol = http
service_host = $CONTROLLER_EXT_IP
service_port = 5000
auth_host = $CONTROLLER_MNG_IP
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
admin_user = cinder
admin_password = service_pass

 /etc/cinder/cinder.conf
[DEFAULT]
rootwrap_config=/etc/cinder/rootwrap.conf
sql_connection = mysql://cinderUser:cinderPass@$CONTROLLER_MNG_IP/cinder
api_paste_config = /etc/cinder/api-paste.ini
iscsi_helper=ietadm
volume_name_template = volume-%s
volume_group = cinder-volumes
verbose = True
auth_strategy = keystone
#osapi_volume_listen_port=5900

cinder-manage db sync

fdisk /dev/sdb
n
p
ENTER
ENTER
ENTER
t
8e?????????????????????????????????????????????
w

pvcreate /dev/sdb
vgcreate cinder-volumes /dev/sdb

?????????????????????I write it as cinder_volume????


####################################################
#Cinder
####################################################
apt-get install -y openstack-dashboard memcached


dpkg --purge openstack-dashboard-ubuntu-theme

service apache2 restart; service memcached restart










