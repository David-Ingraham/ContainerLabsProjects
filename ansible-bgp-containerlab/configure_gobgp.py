#!/usr/bin/env python3
"""
Configure GoBGP via gRPC API
Connects to router management IP and configures BGP
"""

import grpc
import sys
from api import gobgp_pb2, gobgp_pb2_grpc, attribute_pb2, nlri_pb2, common_pb2
from google.protobuf.any_pb2 import Any

def configure_gobgp(router_ip, as_number, router_id, self_ip, neighbor_ip, neighbor_as, advertise_prefix):
    """
    Configure GoBGP router via gRPC API
    
    Args:
        router_ip: Management IP of GoBGP router
        as_number: Local AS number
        router_id: BGP router ID
        self_ip: Local IP on data plane (used as next-hop)
        neighbor_ip: BGP neighbor IP address
        neighbor_as: BGP neighbor AS number
        advertise_prefix: Network prefix to advertise (CIDR notation)
    """
    print(f"Connecting to GoBGP at {router_ip}:50051...")
    
    # Connect to gRPC API with timeout
    channel = grpc.insecure_channel(f'{router_ip}:50051')
    stub = gobgp_pb2_grpc.GoBgpServiceStub(channel)
    
    try:
        # Try to start BGP - if it's already running, we'll get an error we can handle
        print(f"Starting BGP with AS {as_number}, Router-ID {router_id}...")
        
        try:
            # Create the Global config object
            global_obj = gobgp_pb2.Global()
            global_obj.asn = as_number
            global_obj.router_id = router_id
            
            # Create StartBgpRequest and set the 'global' field
            global_config = gobgp_pb2.StartBgpRequest()
            getattr(global_config, 'global').CopyFrom(global_obj)
            
            stub.StartBgp(global_config, timeout=5)
            print("  BGP started successfully")
        except grpc.RpcError as e:
            if "already" in str(e).lower():
                print("  BGP already running, continuing with configuration...")
            else:
                print(f"  Warning starting BGP: {e.code()} - {e.details()}")
                print("  Attempting to continue...")
        
        # Add BGP neighbor (check if already exists first)
        print(f"Adding neighbor {neighbor_ip} (AS {neighbor_as})...")
        try:
            # Try to delete existing peer first
            stub.DeletePeer(gobgp_pb2.DeletePeerRequest(address=neighbor_ip))
            print(f"  Removed existing neighbor {neighbor_ip}")
        except grpc.RpcError:
            pass  # Peer didn't exist, that's fine
        
        neighbor = gobgp_pb2.AddPeerRequest(
            peer=gobgp_pb2.Peer(
                conf=gobgp_pb2.PeerConf(
                    neighbor_address=neighbor_ip,
                    peer_asn=neighbor_as
                )
            )
        )
        stub.AddPeer(neighbor)
        print("  Neighbor added")
        
        # Configure import/export policy to accept all routes
        print("Configuring import/export policy...")
        try:
            # Create a simple statement that accepts all routes
            statement = gobgp_pb2.Statement(
                name="accept-all-stmt",
                actions=gobgp_pb2.Actions(
                    route_action=gobgp_pb2.RouteAction.ROUTE_ACTION_ACCEPT
                )
            )
            
            # Create the policy with the statement
            policy = gobgp_pb2.Policy(
                name="accept-all",
                statements=[statement]
            )
            
            # Try to delete existing policy first
            try:
                stub.DeletePolicy(gobgp_pb2.DeletePolicyRequest(
                    policy=policy,
                    preserve_statements=False
                ))
            except grpc.RpcError:
                pass  # Policy didn't exist
            
            # Add the policy
            stub.AddPolicy(gobgp_pb2.AddPolicyRequest(
                policy=policy,
                refer_existing_statements=False
            ))
            
            # Apply import policy to the neighbor
            stub.AddPolicyAssignment(gobgp_pb2.AddPolicyAssignmentRequest(
                assignment=gobgp_pb2.PolicyAssignment(
                    name=neighbor_ip,
                    direction=gobgp_pb2.PolicyDirection.POLICY_DIRECTION_IMPORT,
                    policies=[policy],
                    default_action=gobgp_pb2.RouteAction.ROUTE_ACTION_ACCEPT
                )
            ))
            
            # Apply export policy to the neighbor  
            stub.AddPolicyAssignment(gobgp_pb2.AddPolicyAssignmentRequest(
                assignment=gobgp_pb2.PolicyAssignment(
                    name=neighbor_ip,
                    direction=gobgp_pb2.PolicyDirection.POLICY_DIRECTION_EXPORT,
                    policies=[policy],
                    default_action=gobgp_pb2.RouteAction.ROUTE_ACTION_ACCEPT
                )
            ))
            
            print("  Import/Export policy configured (accept-all)")
        except grpc.RpcError as e:
            print(f"  Warning configuring policy: {e.details()}")
            print("  Continuing without policy (may reject routes)...")
        
        # Advertise prefix
        print(f"Advertising prefix {advertise_prefix}...")
        prefix_parts = advertise_prefix.split('/')
        prefix_addr = prefix_parts[0]
        prefix_len = int(prefix_parts[1])
        
        # Create NLRI with IPAddressPrefix
        nlri = nlri_pb2.NLRI()
        nlri.prefix.CopyFrom(
            nlri_pb2.IPAddressPrefix(
                prefix_len=prefix_len,
                prefix=prefix_addr
            )
        )
        
        # Create attributes
        origin_attr = attribute_pb2.Attribute()
        origin_attr.origin.CopyFrom(
            attribute_pb2.OriginAttribute(origin=0)  # IGP
        )
        
        next_hop_attr = attribute_pb2.Attribute()
        next_hop_attr.next_hop.CopyFrom(
            attribute_pb2.NextHopAttribute(next_hop=self_ip)
        )
        
        # Create Family for IPv4 Unicast
        family = common_pb2.Family()
        family.afi = 1  # AFI_IP (IPv4)
        family.safi = 1  # SAFI_UNICAST
        
        path = gobgp_pb2.Path()
        path.nlri.CopyFrom(nlri)
        path.pattrs.append(origin_attr)
        path.pattrs.append(next_hop_attr)
        path.family.CopyFrom(family)
        
        stub.AddPath(gobgp_pb2.AddPathRequest(
            table_type=gobgp_pb2.TABLE_TYPE_GLOBAL,
            path=path
        ))
        print("  Prefix advertised")
        
        print(f"\nGoBGP configuration complete for {router_ip}")
        return True
        
    except grpc.RpcError as e:
        print(f"ERROR: gRPC call failed: {e.code()} - {e.details()}")
        return False
    except Exception as e:
        print(f"ERROR: {e}")
        return False

if __name__ == "__main__":
    # Configuration for gobgp1
    # Topology: host1 -- frr1 -- gobgp1 -- host2
    #                      |
    #                    frr2 -- receivers
    success = configure_gobgp(
        router_ip="10.1.1.13",        # GoBGP management IP
        as_number=65002,               # GoBGP AS number
        router_id="2.2.2.2",
        self_ip="10.0.1.3",           # GoBGP's IP on link to frr1
        neighbor_ip="10.0.1.2",       # frr1's IP on the link
        neighbor_as=65001,             # frr1's AS
        advertise_prefix="10.3.0.0/24"  # GoBGP's backend network
    )
    
    sys.exit(0 if success else 1)

