#!/usr/bin/env python3
"""
Create data plane networks for SR Linux multicast lab.
Reads link configuration from inventory.yml and creates Docker networks
connecting hosts to routers.
"""

import subprocess
import sys
import yaml


def run_cmd(cmd, ignore_errors=False):
    """Execute shell command."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if result.returncode != 0 and not ignore_errors:
        print(f"Command failed: {cmd}")
        print(f"stderr: {result.stderr}")
    return result


def load_inventory(path="inventory.yml"):
    """Load and parse inventory.yml."""
    with open(path, "r") as f:
        return yaml.safe_load(f)


def get_lab_name(inventory):
    """Extract lab name from inventory."""
    return inventory.get("all", {}).get("vars", {}).get("lab_name", "srlinux-multicast-lab")


def get_links(inventory):
    """Extract link definitions from inventory."""
    return (
        inventory.get("all", {})
        .get("children", {})
        .get("link_definitions", {})
        .get("vars", {})
        .get("links", [])
    )


def cleanup_networks(lab_name, links):
    """Remove existing networks."""
    print("Cleaning up old networks...")
    for link in links:
        network_name = link.get("name")
        if network_name:
            # Disconnect all containers first
            for conn in link.get("connections", []):
                container = f"clab-{lab_name}-{conn['container']}"
                run_cmd(f"docker network disconnect {network_name} {container}", ignore_errors=True)
            run_cmd(f"docker network rm {network_name}", ignore_errors=True)


def create_networks(lab_name, links):
    """Create Docker networks and connect containers."""
    print("Creating data plane networks...")
    
    for link in links:
        network_name = link.get("name")
        subnet = link.get("subnet")
        connections = link.get("connections", [])
        
        if not network_name or not subnet:
            continue
            
        print(f"\n  Network: {network_name} ({subnet})")
        
        # Create network
        result = run_cmd(f"docker network create --subnet={subnet} {network_name}", ignore_errors=True)
        if result.returncode != 0 and "already exists" not in result.stderr:
            print(f"    Warning: could not create network: {result.stderr}")
            continue
            
        # Connect containers
        for conn in connections:
            container_name = conn.get("container")
            ip = conn.get("ip")
            gateway = conn.get("gateway")
            
            container = f"clab-{lab_name}-{container_name}"
            
            # Connect to network
            cmd = f"docker network connect --ip {ip} {network_name} {container}"
            result = run_cmd(cmd, ignore_errors=True)
            
            if result.returncode == 0:
                print(f"    {container_name}: {ip}")
            elif "already exists" in result.stderr:
                print(f"    {container_name}: {ip} (already connected)")
            else:
                print(f"    {container_name}: failed - {result.stderr.strip()}")
                continue
                
            # Configure gateway for hosts (not routers)
            if gateway:
                run_cmd(f"docker exec {container} ip route del default 2>/dev/null", ignore_errors=True)
                run_cmd(f"docker exec {container} ip route add default via {gateway}")
                print(f"    {container_name}: default route via {gateway}")


def verify_connectivity(lab_name):
    """Basic connectivity check."""
    print("\nVerifying connectivity...")
    
    # Ping from source to srl1
    container = f"clab-{lab_name}-source"
    result = run_cmd(f"docker exec {container} ping -c 1 -W 2 10.11.0.1", ignore_errors=True)
    if result.returncode == 0:
        print("  source -> srl1: OK")
    else:
        print("  source -> srl1: FAILED (may need routing config)")


def main():
    print("Creating data plane networks from inventory.yml...")
    print("")
    
    inventory = load_inventory()
    lab_name = get_lab_name(inventory)
    links = get_links(inventory)
    
    if not links:
        print("No link definitions found in inventory.yml")
        return
    
    cleanup_networks(lab_name, links)
    create_networks(lab_name, links)
    verify_connectivity(lab_name)
    
    print("")
    print("Data plane configuration complete.")


if __name__ == "__main__":
    main()

