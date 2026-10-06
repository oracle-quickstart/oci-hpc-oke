#!/usr/bin/env bash
# IPv6 setup for the RDMA rails on IPv6 clusters with the VCN-Native CNI. OCA sets accept_ra on
# the rails once, from the IPv6 forwarding state, and the CNI turns forwarding on later.
# Runs from cloud-init runcmd on the first boot and from oke-rdma-ipv6.service before OCA after that.
if [ -z "$(ls -A /sys/class/infiniband 2>/dev/null)" ]; then
  exit 0
fi

# The primary NIC keeps its RA default route when forwarding is on.
dev=$(ip -o -4 route show default | awk '{print $5; exit}')
if [ -n "$dev" ]; then
  sysctl -w "net.ipv6.conf.${dev}.accept_ra=2"
fi

# Forwarding first, so OCA picks accept_ra=2 for the rails. Set it here too, in case OCA already ran.
sysctl -w net.ipv6.conf.all.forwarding=1
for nic in /sys/class/net/rdma*; do
  if [ -e "$nic" ]; then
    sysctl -w "net.ipv6.conf.${nic##*/}.accept_ra=2"
  fi
done

# OCA IPv6 policy routing moves the local rule to priority 30000, so traffic the host did not
# send (pods to Service IPs) looks up local addresses first again.
if [ -z "$(ip -6 rule show pref 100)" ]; then
  ip -6 rule add pref 100 not iif lo lookup local
fi
