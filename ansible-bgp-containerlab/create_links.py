#!/usr/bin/env python3
"""
Create data plane and backend networks for BGP lab.
Reads network configuration from inventory.yml and executes docker commands.
Replaces create-links.sh with a data-driven approach.
"""

import subprocess
import sys
import yaml


def run_cmd(cmd, ignore_errors=False):
    """Execute shell command, optionally ignoring errors."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0 and not ignore_errors:
        print(f"Command failed: {cmd}")
        print(f"stderr: {result.stderr}")
    return result


def load_inventory(path="inventory.yml"):
    """Load and parse inventory.yml."""
    with open(path, "r") as f:
        return yaml.safe_load(f)


def get_lab_vars(inventory):
    """Extract lab-level variables."""
    return inventory.get("all", {}).get("vars", {})


def get_all_routers(inventory):
    """Extract all router hosts from inventory."""
    routers = {}
    children = inventory.get("all", {}).get("children", {}).get("routers", {}).get("children", {})
    
    for group_name, group_data in children.items():
        hosts = group_data.get("hosts", {})
        for host_name, host_vars in hosts.items():
            routers[host_name] = host_vars
    
    return routers


def cleanup_networks(lab_name, routers, data_plane_network):
    """Clean up existing network connections."""
    print("Cleaning up old connections...")
    
    # Disconnect from data plane network
    for router_name in routers:
        container = f"clab-{lab_name}-{router_name}"
        run_cmd(f"docker network disconnect {data_plane_network} {container}", ignore_errors=True)
    
    run_cmd(f"docker network rm {data_plane_network}", ignore_errors=True)
    
    # Clean up backend networks
    for router_name, router_vars in routers.items():
        backend_network = router_vars.get("backend_network_name")
        if backend_network:
            container = f"clab-{lab_name}-{router_name}"
            run_cmd(f"docker network disconnect {backend_network} {container}", ignore_errors=True)
            
            # Disconnect hosts
            for host in router_vars.get("backend_hosts", []):
                host_container = f"clab-{lab_name}-{host['name']}"
                run_cmd(f"docker network disconnect {backend_network} {host_container}", ignore_errors=True)
            
            run_cmd(f"docker network rm {backend_network}", ignore_errors=True)


def check_subnet_conflicts(subnet):
    """Find and remove networks with conflicting subnets."""
    print(f"Checking for conflicting networks with subnet {subnet}...")
    
    result = run_cmd("docker network ls --format '{{.Name}}'", ignore_errors=True)
    if result.returncode != 0:
        return
    
    for net in result.stdout.strip().split("\n"):
        if not net:
            continue
        inspect = run_cmd(f"docker network inspect {net}", ignore_errors=True)
        if subnet.split("/")[0] in inspect.stdout:
            print(f"  Removing conflicting network: {net}")
            # Disconnect all containers first
            containers_result = run_cmd(
                f"docker network inspect {net} --format '{{{{range .Containers}}}}{{{{.Name}}}} {{{{end}}}}'",
                ignore_errors=True
            )
            for container in containers_result.stdout.strip().split():
                if container:
                    print(f"    Disconnecting container: {container}")
                    run_cmd(f"docker network disconnect {net} {container}", ignore_errors=True)
            run_cmd(f"docker network rm {net}", ignore_errors=True)


def create_data_plane(lab_name, routers, network_name, subnet):
    """Create data plane network and connect routers."""
    print(f"Creating data plane network {network_name} ({subnet})...")
    
    check_subnet_conflicts(subnet)
    run_cmd(f"docker network create --subnet={subnet} {network_name}")
    
    print("Connecting routers to data plane...")
    for router_name, router_vars in routers.items():
        data_plane_ip = router_vars.get("data_plane_ip")
        if data_plane_ip:
            container = f"clab-{lab_name}-{router_name}"
            run_cmd(f"docker network connect --ip {data_plane_ip} {network_name} {container}")
            print(f"  {router_name}: {data_plane_ip}")


def create_backend_networks(lab_name, routers):
    """Create backend networks and connect routers and hosts."""
    print("\nCreating backend networks...")
    
    for router_name, router_vars in routers.items():
        backend_network = router_vars.get("backend_network_name")
        advertise_network = router_vars.get("advertise_network")
        backend_ip = router_vars.get("backend_ip")
        backend_hosts = router_vars.get("backend_hosts", [])
        
        if not all([backend_network, advertise_network, backend_ip]):
            continue
        
        print(f"  Creating {backend_network} ({advertise_network})...")
        run_cmd(f"docker network create --subnet={advertise_network} {backend_network}", ignore_errors=True)
        
        # Connect router
        container = f"clab-{lab_name}-{router_name}"
        run_cmd(f"docker network connect --ip {backend_ip} {backend_network} {container}", ignore_errors=True)
        print(f"    {router_name}: {backend_ip}")
        
        # Connect hosts
        for host in backend_hosts:
            host_container = f"clab-{lab_name}-{host['name']}"
            run_cmd(f"docker network connect --ip {host['ip']} {backend_network} {host_container}", ignore_errors=True)
            print(f"    {host['name']}: {host['ip']}")
            
            # Configure host routing
            run_cmd(f"docker exec {host_container} ip route del default", ignore_errors=True)
            run_cmd(f"docker exec {host_container} ip route add default via {backend_ip}", ignore_errors=True)


def verify_connectivity(lab_name, routers):
    """Verify data plane connectivity between routers."""
    print("\nVerifying connectivity...")
    
    router_list = list(routers.items())
    if len(router_list) >= 2:
        first_router = router_list[0][0]
        second_router_ip = router_list[1][1].get("data_plane_ip")
        if second_router_ip:
            container = f"clab-{lab_name}-{first_router}"
            result = run_cmd(f"docker exec {container} ping -c 2 {second_router_ip}", ignore_errors=True)
            if result.returncode != 0:
                print("  Note: Ping may fail until routing is configured")


def main():
    print("Creating data plane networks from inventory.yml...")
    print("")
    
    inventory = load_inventory()
    lab_vars = get_lab_vars(inventory)
    routers = get_all_routers(inventory)
    
    lab_name = lab_vars.get("lab_name", "bgp-lab")
    data_plane_network = lab_vars.get("data_plane_network", "bgp-dataplane")
    data_plane_subnet = lab_vars.get("data_plane_subnet", "10.0.1.0/29")
    
    cleanup_networks(lab_name, routers, data_plane_network)
    create_data_plane(lab_name, routers, data_plane_network, data_plane_subnet)
    create_backend_networks(lab_name, routers)
    verify_connectivity(lab_name, routers)
    
    print("")
    print("Data plane configuration complete.")


if __name__ == "__main__":
    main()

