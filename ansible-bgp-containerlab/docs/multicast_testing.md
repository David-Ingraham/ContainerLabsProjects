# Multicast Testing Guide

## Configuration Summary

- **RP (Rendezvous Point)**: frr1 (1.1.1.1)
- **Multicast Group**: 239.1.1.1
- **Source**: host1 (10.1.0.10) behind frr1 (FHR)
- **Receivers**: receiver1, receiver2 (10.2.0.10, 10.2.0.20) behind frr2 (LHR)

## Configuration Steps

### 1. Deploy Lab
```bash
cd scripts/shell
./setup.sh
```

### 2. Configure BGP (Required for RPF checks)
```bash
cd ansible/playbooks
ansible-playbook -i ../inventory.yml config_playbook.yml
```
This now includes PIM configuration at the end.

### 3. Verify Multicast Setup
```bash
cd scripts/shell
./verify-multicast.sh
```

Check for:
- PIM neighbors established between frr1 and frr2
- PIM enabled on all required interfaces
- RP configured as 1.1.1.1 on both routers
- IGMP enabled on frr2's receiver-facing interface

## Testing Multicast Traffic

### Terminal 1: Start Receiver
```bash
cd scripts/shell
./test-multicast-receiver.sh receiver1
```
This joins group 239.1.1.1 and waits for packets.

### Terminal 2: Start Another Receiver (Optional)
```bash
cd scripts/shell
./test-multicast-receiver.sh receiver2
```

### Terminal 3: Start Source
```bash
cd scripts/shell
./test-multicast-source.sh
```
This sends packets to 239.1.1.1 every 2 seconds.

### Terminal 4: Monitor Multicast State
```bash
cd scripts/shell
./verify-multicast.sh
```

Look for:
- IGMP group membership on frr2
- Multicast routes (mroutes) on both routers
- PIM state showing (S,G) entries

## Expected Behavior

### Before Source Starts
- IGMP membership appears on frr2 when receivers join
- PIM (*,G) state created (shared tree via RP)
- frr2 sends PIM Join toward RP (frr1)

### After Source Starts
- frr1 registers traffic with RP (itself)
- Multicast routes (S,G) appear on both routers
- Traffic flows: host1 → frr1 → frr2 → receivers
- Both receiver1 and receiver2 receive packets

### Verification Commands

On frr1 (FHR):
```bash
docker exec clab-bgp-lab-frr1 vtysh -c "show ip pim neighbor"
docker exec clab-bgp-lab-frr1 vtysh -c "show ip mroute"
docker exec clab-bgp-lab-frr1 vtysh -c "show ip pim state"
```

On frr2 (LHR):
```bash
docker exec clab-bgp-lab-frr2 vtysh -c "show ip igmp groups"
docker exec clab-bgp-lab-frr2 vtysh -c "show ip mroute"
docker exec clab-bgp-lab-frr2 vtysh -c "show ip pim state"
```

## Troubleshooting

### No PIM Neighbors
- Check PIM enabled on interfaces: `show ip pim interface`
- Verify unicast connectivity between routers
- Check firewall/security settings

### Receivers Not Getting Traffic
- Verify IGMP membership: `show ip igmp groups` on frr2
- Check mroute table has correct outgoing interfaces
- Verify RPF check passes: `show ip rpf <source-ip>`
- Check that source is actually sending traffic

### RP Issues
- Verify RP configured on all routers: `show ip pim rp-info`
- Ensure all routers point to same RP (1.1.1.1)
- Check unicast routing to RP address

## PowerShell (Windows)

Same steps but use .ps1 scripts:
```powershell
.\test-multicast-receiver.ps1 receiver1
.\test-multicast-source.ps1
.\verify-multicast.ps1
```

## Packet Flow

```
host1 (10.1.0.10)
    |
    | IGMP/UDP to 239.1.1.1
    |
frr1 (FHR) - eth2: receives from source
    |        - encapsulates in PIM Register → RP (itself)
    |        - creates (S,G) mroute entry
    |        - RPF check: source on correct interface?
    |
    | Forwards multicast to frr2
    |
frr2 (LHR) - eth1: receives from frr1
    |        - RPF check passes
    |        - has IGMP members on eth2
    |        - forwards to receiver subnet
    |
    | Floods to 10.2.0.0/24 subnet
    |
receiver1 (10.2.0.10) - joined group 239.1.1.1
receiver2 (10.2.0.20) - joined group 239.1.1.1
```

## Key Tables to Monitor

1. **PIM Neighbor Table**: Shows PIM-speaking routers
2. **IGMP Membership Table**: Shows which interfaces have group members
3. **Multicast Route Table (mroute)**: Shows (S,G) forwarding state
4. **PIM State**: Shows active multicast flows

## Notes

- Multicast uses UDP (no TCP handshake/ACK)
- TTL must be > 1 for traffic to reach receivers (set to 32)
- IGMP reports are sent by receivers to local subnet
- PIM Join messages propagate hop-by-hop toward source/RP
- RPF check uses unicast routing table (BGP routes)
