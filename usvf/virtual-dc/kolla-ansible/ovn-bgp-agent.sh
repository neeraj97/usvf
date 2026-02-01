
# not script just doc
sudo apt install openvswitch-switch
sudo apt install ovn-bgp-agent
# Make sure br-ex is up
# Make sure br-int is up
# Make sure bgp-nic is up
# Make sure bgp-vrf is up

# Need to create Systemd file for below command or run directly for testing
sudo ovn-bgp-agent --config-file /etc/ovn-bgp-agent/bgp-agent.conf

# /etc/ovn-bgp-agent/bgp-agent.conf
[DEFAULT]
# debug = True
# Core behavior
driver = nb_ovn_bgp_driver
exposing_method = underlay

# IMPORTANT: do not leak tenant IPs
expose_tenant_networks = false
expose_ipv6_gua_tenant_networks = false

# OVSDB socket (set this to the real one on your host)
ovsdb_connection = unix:/var/run/openvswitch/db.sock

# Where the agent will “attach” /32s
bgp_nic = bgp-nic
bgp_vrf = bgp-vrf
bgp_vrf_table_id = 10

# Optional: cleanup behavior
clear_vrf_routes_on_startup = false

bgp_AS = 65005
bgp_router_id = 10.1.0.5

[ovn]
# Point these to your OVN DB endpoints (Kolla runs these on controllers)
ovn_nb_connection = tcp:10.100.0.254:6641
ovn_sb_connection = tcp:10.100.0.254:6642