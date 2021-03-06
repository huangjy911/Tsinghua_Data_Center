#!/bin/sh
#
# Quantum Networking
#
# Description: Create Virtual Networking for Quantum
# 
# Designed for "Provider Router with Private Networks" Use-Case (http://goo.gl/JTt5n)


###########################
### Private Network #######
###########################

TENANT_NAME="proj1"             # The tenant this network is created for
USER_NAME="user1"
TENANT_NETWORK_NAME="net_proj1" # The Quantum-internal network name
FIXED_RANGE="192.168.50.0/24"	# The IP range for the private tenant network
NETWORK_GATEWAY="192.168.50.1"	# The Gateway Tenant-VMs will receive as default gw

##############################################################
### Public Network ###########################################
##############################################################

# Provider Router Information - what name should 
# this provider have in Quantum?
PROV_ROUTER_NAME="router_proj1"

# Name of External Network (Don't change it!)
EXT_NET_NAME="ext_net"

# External Network addressing - our official 
# Internet IP address space
EXT_NET_CIDR="10.10.0.0/24"
EXT_NET_LEN=${EXT_NET_CIDR#*/}

# External bridge that we have configured 
# into l3_agent.ini (Don't change it!)
EXT_NET_BRIDGE=br-ex

# IP of external bridge (br-ex) - this node's 
# IP in our official Internet IP address space:
EXT_GW_IP="10.10.0.201"

# IP of the Public Network Gateway - The 
# default GW in our official Internet IP address space:
EXT_NET_GATEWAY="10.10.0.1"

# Floating IP range
POOL_FLOATING_START="10.10.0.20"	# First public IP to be used for VMs
POOL_FLOATING_END="10.10.0.40"	# Last public IP to be used for VMs 

###############################################################

# Function to get ID :
get_id () {
        echo `$@ | awk '/ id / { print $4 }'`
}

create_user(){
    local tenant_name="$1"
    local username="$2"
    local role_id=$(keystone role-list | grep "Member" | awk '{print $2}')
    local tmptenant_id=$(get_id keystone tenant-create --name $tenant_name)
    user_id=$(get_id keystone user-create --name=$username --pass=$username --tenant-id $tmptenant_id --email=$username@domain.com)
    keystone user-role-add --tenant-id $tmptenant_id  --user-id $user_id --role-id $role_id
}

# Create the Tenant private network :
create_net() {
    local tenant_name="$1"
    local tenant_network_name="$2"
    local prov_router_name="$3"
    local fixed_range="$4"
    local network_gateway="$5"
    local tenant_id=$(keystone tenant-list | grep " $tenant_name " | awk '{print $2}')

    tenant_net_id=$(get_id quantum net-create --tenant_id $tenant_id $tenant_network_name --provider:network_type vlan --provider:physical_network physnet1 --provider:segmentation_id 1024)
    tenant_subnet_id=$(get_id quantum subnet-create --tenant_id $tenant_id $tenant_network_name $fixed_range --dns_nameservers list=true 166.111.8.28 8.8.8.8)
    prov_router_id=$(get_id quantum router-create --tenant_id $tenant_id $prov_router_name)

    quantum router-interface-add $prov_router_id $tenant_subnet_id
}

# Create External Network :
create_ext_net() {
    local ext_net_name="$1"
    local ext_net_cidr="$2"
    local ext_net_gateway="$4"
    local pool_floating_start="$5"
    local pool_floating_end="$6"

    local service_tenant_id=$(keystone tenant-list | grep "service" | awk '{print $2}')

    ext_net_id=$(get_id quantum net-create --tenant-id $service_tenant_id $ext_net_name --router:external=True)
    quantum subnet-create --tenant-id $service_tenant_id --allocation-pool start=$pool_floating_start,end=$pool_floating_end --gateway $ext_net_gateway $ext_net_name $ext_net_cidr -- --enable_dhcp=False
}

# Connect the Tenant Virtual Router to External Network :
connect_providerrouter_to_externalnetwork() {
    local prov_router_name="$1"
    local ext_net_name="$2"

    router_id=$(get_id quantum router-show $prov_router_name)
    ext_net_id=$(get_id quantum net-show $ext_net_name)
    quantum router-gateway-set $router_id $ext_net_id

}

create_user $TENANT_NAME $USER_NAME
create_net $TENANT_NAME $TENANT_NETWORK_NAME $PROV_ROUTER_NAME $FIXED_RANGE $NETWORK_GATEWAY
create_ext_net $EXT_NET_NAME $EXT_NET_CIDR $EXT_NET_BRIDGE $EXT_NET_GATEWAY $POOL_FLOATING_START $POOL_FLOATING_END
connect_providerrouter_to_externalnetwork $PROV_ROUTER_NAME $EXT_NET_NAME

# Configure br-ex to reach public network :
#ip addr flush dev $EXT_NET_BRIDGE
#ip addr add $EXT_GW_IP/$EXT_NET_LEN dev $EXT_NET_BRIDGE
#ip link set $EXT_NET_BRIDGE up


