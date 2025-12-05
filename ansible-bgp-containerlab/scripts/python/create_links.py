#!/usr/bin/env python3
"""
Create data plane networks for BGP/Multicast lab.
Reads network configuration from inventory.yml and executes docker commands.

Network Types:
1. Router Links - Point-to-point between routers in different autonomous systems
   (e.g., frr1 <-> gobgp1). Used when routers have no other shared network.
2. Backend Networks - Connect hosts to their gateway router. Routers in the same
   routing domain may share a backend network instead of a dedicated link
   (e.g., frr2 connects to frr1 via frr1-network).

Multicast Note:
These networks form the physical topology. PIM will build a logical
multicast distribution tree on top of this, pruning paths where
there are no interested receivers.
"""

import os
import subprocess
import sys
import time
import yaml


def run_cmd(cmd, ignore_errors=False, show_output=False):
    """Execute shell command, optionally ignoring errors."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0 and not ignore_errors:
        print(f"    [ERROR] Command: {cmd}")
        print(f"    [ERROR] Exit code: {result.returncode}")
        if result.stderr.strip():
            print(f"    [ERROR] stderr: {result.stderr.strip()}")
        if result.stdout.strip():
            print(f"    [ERROR] stdout: {result.stdout.strip()}")
    elif show_output and result.stdout.strip():
        print(f"    {result.stdout.strip()}")
    return result


def is_container_on_network(container, network_name):
    """Check if a container is connected to a specific Docker network."""
    result = run_cmd(
        f"docker network inspect {network_name} --format '{{{{range .Containers}}}}{{{{.Name}}}} {{{{end}}}}'",
        ignore_errors=True
    )
    if result.returncode == 0:
        return container in result.stdout
    return False


def load_inventory(path=None):
    """Load and parse inventory.yml."""
    if path is None:
        # Script is in scripts/python/, inventory is in ansible/
        script_dir = os.path.dirname(os.path.abspath(__file__))
        project_dir = os.path.dirname(os.path.dirname(script_dir))
        path = os.path.join(project_dir, "ansible", "inventory.yml")
    with open(path, "r") as f:
        return yaml.safe_load(f)


def get_lab_name(inventory):
    """Extract lab name from inventory."""
    return inventory.get("all", {}).get("vars", {}).get("lab_name", "bgp-lab")


def get_router_links(inventory):
    """Extract router-to-router link definitions."""
    return inventory.get("all", {}).get("vars", {}).get("router_links", [])


def get_frr_routers(inventory):
    """Extract FRR router configurations."""
    return (
        inventory.get("all", {})
        .get("children", {})
        .get("routers", {})
        .get("children", {})
        .get("frr_routers", {})
        .get("hosts", {})
    )


def get_all_router_names(inventory):
    """Get names of all routers (FRR + GoBGP) to identify them vs hosts."""
    router_names = set()
    
    # FRR routers
    frr = get_frr_routers(inventory)
    router_names.update(frr.keys())
    
    # GoBGP routers
    gobgp = (
        inventory.get("all", {})
        .get("children", {})
        .get("routers", {})
        .get("children", {})
        .get("gobgp_routers", {})
        .get("hosts", {})
    )
    router_names.update(gobgp.keys())
    
    return router_names


def cleanup_networks(lab_name, router_links, routers):
    """Remove existing networks to start fresh."""
    print("Cleaning up old networks...")
    
    # Clean router links
    for link in router_links:
        network_name = link.get("name")
        if network_name:
            for endpoint in link.get("endpoints", []):
                container = f"clab-{lab_name}-{endpoint['router']}"
                run_cmd(f"docker network disconnect {network_name} {container}", ignore_errors=True)
            run_cmd(f"docker network rm {network_name}", ignore_errors=True)
    
    # Clean backend networks
    for router_name, router_vars in routers.items():
        backend_network = router_vars.get("backend_network_name")
        if backend_network:
            container = f"clab-{lab_name}-{router_name}"
            run_cmd(f"docker network disconnect {backend_network} {container}", ignore_errors=True)
            
            for host in router_vars.get("backend_hosts", []):
                host_container = f"clab-{lab_name}-{host['name']}"
                run_cmd(f"docker network disconnect {backend_network} {host_container}", ignore_errors=True)
            
            run_cmd(f"docker network rm {backend_network}", ignore_errors=True)


def network_exists(network_name):
    """Check if a Docker network exists."""
    result = run_cmd(f"docker network inspect {network_name}", ignore_errors=True)
    return result.returncode == 0


def get_network_subnet(network_name):
    """Get the subnet of an existing network."""
    result = run_cmd(
        f'docker network inspect {network_name} --format "{{{{range .IPAM.Config}}}}{{{{.Subnet}}}}{{{{end}}}}"',
        ignore_errors=True
    )
    return result.stdout.strip() if result.returncode == 0 else None


def create_router_links(lab_name, router_links):
    """
    Create point-to-point networks between routers.
    
    These links form the backbone of the network. In multicast terms,
    PIM messages travel over these links to build the distribution tree.
    """
    print("\nCreating router-to-router links...")
    print("(These form the multicast distribution tree backbone)")
    
    for link in router_links:
        network_name = link.get("name")
        subnet = link.get("subnet")
        endpoints = link.get("endpoints", [])
        
        if not network_name or not subnet:
            continue
        
        print(f"\n  {network_name} ({subnet}):")
        
        # Check if network exists
        if network_exists(network_name):
            existing_subnet = get_network_subnet(network_name)
            if existing_subnet == subnet:
                print(f"    Network already exists with correct subnet, reusing")
            else:
                print(f"    [CONFLICT] Network exists with different subnet: {existing_subnet}")
                print(f"    Disconnecting all containers and removing...")
                # Disconnect all containers from this network first
                containers = run_cmd(
                    f"docker network inspect {network_name} --format '{{{{range .Containers}}}}{{{{.Name}}}} {{{{end}}}}'",
                    ignore_errors=True
                )
                for container in containers.stdout.strip().split():
                    if container:
                        run_cmd(f"docker network disconnect -f {network_name} {container}", ignore_errors=True)
                # Now remove
                run_cmd(f"docker network rm {network_name}", ignore_errors=True)
                # Wait a moment for Docker to release resources
                import time
                time.sleep(1)
                result = run_cmd(f"docker network create --subnet={subnet} {network_name}")
                if result.returncode != 0:
                    print(f"    [FAILED] Could not recreate network: {result.stderr.strip()}")
                    continue
                print(f"    Network recreated")
        else:
            # Check for subnet conflicts with other networks
            result = run_cmd(f"docker network create --subnet={subnet} {network_name}", ignore_errors=True)
            if result.returncode != 0:
                if "Pool overlaps" in result.stderr:
                    print(f"    [CONFLICT] Subnet {subnet} overlaps with another network")
                    print(f"    Searching for conflicting network...")
                    # Find the conflicting network
                    networks = run_cmd("docker network ls --format '{{.Name}}'", ignore_errors=True)
                    for net in networks.stdout.strip().split('\n'):
                        if net and get_network_subnet(net) == subnet:
                            print(f"    Found conflict: {net}")
                    continue
                else:
                    print(f"    [FAILED] {result.stderr.strip()}")
                    continue
            print(f"    Network created")
        
        # Connect routers
        for endpoint in endpoints:
            router = endpoint.get("router")
            ip = endpoint.get("ip")
            container = f"clab-{lab_name}-{router}"
            
            # First check if container exists
            container_check = run_cmd(f"docker inspect {container}", ignore_errors=True)
            if container_check.returncode != 0:
                print(f"    {router}: [ERROR] Container {container} not found")
                continue
            
            result = run_cmd(f"docker network connect --ip {ip} {network_name} {container}", ignore_errors=True)
            if result.returncode == 0:
                print(f"    {router}: {ip} [OK]")
            elif "already exists" in result.stderr or "already connected" in result.stderr.lower():
                print(f"    {router}: {ip} (already connected)")
            else:
                print(f"    {router}: {ip} [FAILED] {result.stderr.strip()}")


def create_backend_networks(lab_name, routers, all_router_names):
    """
    Create backend networks connecting hosts to routers.
    
    Multicast Roles:
    - Source network (behind FHR): Where multicast source sends traffic
    - Receiver network (behind LHR): Where receivers join groups via IGMP
    
    Note: If a "backend host" is actually a router (in all_router_names),
    we don't set a default route on it - routers need their own routing.
    """
    print("\nCreating backend networks...")
    print("(Source and receiver networks for multicast)")
    
    for router_name, router_vars in routers.items():
        backend_network = router_vars.get("backend_network_name")
        backend_subnet = router_vars.get("backend_subnet")
        backend_ip = router_vars.get("backend_ip")
        backend_hosts = router_vars.get("backend_hosts", [])
        
        if not backend_network or not backend_subnet:
            continue
        
        print(f"\n  {backend_network} ({backend_subnet}) - gateway {router_name}:")
        
        # Create or reuse network
        if network_exists(backend_network):
            existing_subnet = get_network_subnet(backend_network)
            if existing_subnet == backend_subnet:
                print(f"    Network exists, reusing")
            else:
                print(f"    [CONFLICT] Network has subnet {existing_subnet}, need {backend_subnet}")
                print(f"    Removing and recreating...")
                run_cmd(f"docker network rm {backend_network}", ignore_errors=True)
                result = run_cmd(f"docker network create --subnet={backend_subnet} {backend_network}")
                if result.returncode != 0:
                    print(f"    [FAILED] Could not create network: {result.stderr.strip()}")
                    continue
        else:
            result = run_cmd(f"docker network create --subnet={backend_subnet} {backend_network}", ignore_errors=True)
            if result.returncode != 0:
                if "Pool overlaps" in result.stderr:
                    print(f"    [CONFLICT] Subnet {backend_subnet} overlaps with another network")
                else:
                    print(f"    [FAILED] {result.stderr.strip()}")
                continue
            print(f"    Network created")
        
        # Connect router as gateway
        container = f"clab-{lab_name}-{router_name}"
        
        # Check if already connected to THIS specific network
        if is_container_on_network(container, backend_network):
            print(f"    {router_name} (gateway): {backend_ip} (already on network)")
        else:
            result = run_cmd(f"docker network connect --ip {backend_ip} {backend_network} {container}", ignore_errors=True)
            if result.returncode == 0:
                print(f"    {router_name} (gateway): {backend_ip} [OK]")
            elif "Address already in use" in result.stderr:
                # Docker reserves .1 for bridge gateway - suggest using .2
                print(f"    {router_name} (gateway): [FAILED] IP {backend_ip} in use (Docker reserves .1 for gateway, use .2)")
            elif "already" in result.stderr.lower():
                print(f"    {router_name} (gateway): {backend_ip} (already connected)")
            else:
                print(f"    {router_name} (gateway): [FAILED] {result.stderr.strip()}")
        
        # Connect hosts (and other routers that share this network)
        for host in backend_hosts:
            host_name = host.get("name")
            host_ip = host.get("ip")
            host_container = f"clab-{lab_name}-{host_name}"
            is_router = host_name in all_router_names
            
            # Check if container exists
            container_check = run_cmd(f"docker inspect {host_container}", ignore_errors=True)
            if container_check.returncode != 0:
                print(f"    {host_name}: [ERROR] Container not found")
                continue
            
            result = run_cmd(f"docker network connect --ip {host_ip} {backend_network} {host_container}", ignore_errors=True)
            if result.returncode == 0:
                print(f"    {host_name}: {host_ip} [OK]" + (" (router)" if is_router else ""))
                
                # Only set default route for hosts, not routers
                if not is_router:
                    run_cmd(f"docker exec {host_container} ip route del default", ignore_errors=True)
                    route_result = run_cmd(f"docker exec {host_container} ip route add default via {backend_ip}", ignore_errors=True)
                    if route_result.returncode == 0:
                        print(f"    {host_name}: default route via {backend_ip}")
                    elif "File exists" in route_result.stderr:
                        print(f"    {host_name}: default route already set")
            elif "already" in result.stderr.lower():
                print(f"    {host_name}: {host_ip} (already connected)")
            else:
                print(f"    {host_name}: [FAILED] {result.stderr.strip()}")


def enable_ip_forwarding(lab_name, routers):
    """Enable IP forwarding on all routers (required for routing and multicast)."""
    print("\nEnabling IP forwarding on routers...")
    
    for router_name in routers:
        container = f"clab-{lab_name}-{router_name}"
        run_cmd(f"docker exec {container} sysctl -w net.ipv4.ip_forward=1", ignore_errors=True)
        print(f"  {router_name}: ip_forward=1")


def verify_connectivity(lab_name, router_links):
    """Basic connectivity check between adjacent routers."""
    print("\nVerifying router connectivity...")
    
    for link in router_links:
        endpoints = link.get("endpoints", [])
        if len(endpoints) >= 2:
            src_router = endpoints[0].get("router")
            dst_ip = endpoints[1].get("ip")
            container = f"clab-{lab_name}-{src_router}"
            
            result = run_cmd(f"docker exec {container} ping -c 1 -W 2 {dst_ip}", ignore_errors=True)
            status = "OK" if result.returncode == 0 else "FAILED"
            print(f"  {link.get('name')}: {src_router} -> {dst_ip}: {status}")


def show_network_diagnostics(lab_name):
    """Show current state of Docker networks for debugging."""
    print("\n" + "-"*60)
    print("Network Diagnostics")
    print("-"*60)
    
    # Show all networks that might be related
    print("\nDocker networks (filtered):")
    result = run_cmd("docker network ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}'", ignore_errors=True)
    for line in result.stdout.strip().split('\n'):
        # Show header or networks related to our lab
        if 'NAME' in line or lab_name in line or 'link-' in line or 'source' in line or 'receiver' in line:
            print(f"  {line}")
    
    # Show container network connections
    print(f"\nContainer network attachments (clab-{lab_name}-*):")
    containers = run_cmd(f"docker ps --filter 'name=clab-{lab_name}' --format '{{{{.Names}}}}'", ignore_errors=True)
    for container in containers.stdout.strip().split('\n'):
        if container:
            networks = run_cmd(
                f"docker inspect {container} --format '{{{{range $net, $config := .NetworkSettings.Networks}}}}{{{{$net}}}} ({{{{$config.IPAddress}}}}) {{{{end}}}}'",
                ignore_errors=True
            )
            print(f"  {container.replace(f'clab-{lab_name}-', '')}: {networks.stdout.strip()}")


def get_gobgp_routers(inventory):
    """Extract GoBGP router configurations."""
    return (
        inventory.get("all", {})
        .get("children", {})
        .get("routers", {})
        .get("children", {})
        .get("gobgp_routers", {})
        .get("hosts", {})
    )


def main():
    print("="*60)
    print("Creating Data Plane Networks from inventory.yml")
    print("="*60)
    
    inventory = load_inventory()
    lab_name = get_lab_name(inventory)
    router_links = get_router_links(inventory)
    frr_routers = get_frr_routers(inventory)
    gobgp_routers = get_gobgp_routers(inventory)
    
    # Combine all routers for backend network processing
    all_routers = {**frr_routers, **gobgp_routers}
    all_router_names = get_all_router_names(inventory)
    
    print(f"\nLab: {lab_name}")
    print(f"Router links: {len(router_links)}")
    print(f"FRR routers: {len(frr_routers)}")
    print(f"GoBGP routers: {len(gobgp_routers)}")
    
    cleanup_networks(lab_name, router_links, all_routers)
    create_router_links(lab_name, router_links)
    create_backend_networks(lab_name, all_routers, all_router_names)
    enable_ip_forwarding(lab_name, frr_routers)  # Only FRR needs this
    verify_connectivity(lab_name, router_links)
    
    # Show diagnostics if there were issues
    show_network_diagnostics(lab_name)
    


if __name__ == "__main__":
    main()
