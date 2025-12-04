#!/usr/bin/env python3
"""
Configure SR Linux via JSON-RPC API

SR Linux exposes a JSON-RPC API on port 80/443 that accepts CLI commands
and returns structured JSON responses. This is similar to Arista's eAPI.

Authentication: Basic auth (username/password)
No API keys - just credentials in the HTTP request.

Compare to GoBGP:
- GoBGP: gRPC on port 50051, protobuf serialization, no auth
- SR Linux: JSON-RPC on port 80, JSON serialization, basic auth
"""

import json
import requests
from requests.auth import HTTPBasicAuth
import yaml
import sys

# Disable SSL warnings for lab environment
requests.packages.urllib3.disable_warnings()


class SRLinuxClient:
    """JSON-RPC client for Nokia SR Linux."""
    
    def __init__(self, host, username="admin", password="NokiaSrl1!", port=80, use_ssl=False):
        """
        Initialize SR Linux JSON-RPC client.
        
        Args:
            host: SR Linux management IP
            username: Login username (default: admin)
            password: Login password (default: NokiaSrl1!)
            port: JSON-RPC port (default: 80)
            use_ssl: Use HTTPS (default: False for lab)
        """
        self.host = host
        self.auth = HTTPBasicAuth(username, password)
        protocol = "https" if use_ssl else "http"
        self.url = f"{protocol}://{host}:{port}/jsonrpc"
        self.request_id = 0
        
    def _call(self, method, params=None):
        """Make JSON-RPC call."""
        self.request_id += 1
        payload = {
            "jsonrpc": "2.0",
            "id": self.request_id,
            "method": method,
            "params": params or {}
        }
        
        headers = {"Content-Type": "application/json"}
        
        try:
            response = requests.post(
                self.url,
                json=payload,
                auth=self.auth,
                headers=headers,
                verify=False,
                timeout=30
            )
            response.raise_for_status()
            result = response.json()
            
            if "error" in result:
                raise Exception(f"JSON-RPC error: {result['error']}")
                
            return result.get("result", {})
            
        except requests.exceptions.RequestException as e:
            raise Exception(f"HTTP request failed: {e}")
    
    def cli(self, commands, output_format="json"):
        """
        Execute CLI commands via JSON-RPC.
        
        Args:
            commands: List of CLI commands to execute
            output_format: Output format (json, text, table)
            
        Returns:
            List of command results
        """
        if isinstance(commands, str):
            commands = [commands]
            
        params = {
            "commands": commands,
            "output-format": output_format
        }
        
        return self._call("cli", params)
    
    def get(self, paths, datastore="running"):
        """
        Get configuration/state data using paths.
        
        Args:
            paths: List of YANG paths to retrieve
            datastore: Which datastore (running, state, candidate)
            
        Returns:
            Retrieved data
        """
        if isinstance(paths, str):
            paths = [paths]
            
        params = {
            "commands": [{"path": p, "datastore": datastore} for p in paths]
        }
        
        return self._call("get", params)
    
    def set(self, updates, datastore="candidate"):
        """
        Set configuration data.
        
        Args:
            updates: List of {path, value} dicts
            datastore: Target datastore
            
        Returns:
            Result of set operation
        """
        params = {
            "commands": updates,
            "datastore": datastore
        }
        
        return self._call("set", params)
    
    def validate(self):
        """Validate candidate configuration."""
        return self._call("validate", {})
    
    def commit(self):
        """Commit candidate configuration to running."""
        return self._call("commit", {})
    
    def discard(self):
        """Discard candidate configuration changes."""
        return self._call("discard", {})


def get_system_info(client):
    """Get system information."""
    print("Getting system information...")
    
    result = client.cli(["info from state system information"])
    print(json.dumps(result, indent=2))
    return result


def get_interfaces(client):
    """Get interface status."""
    print("\nGetting interface status...")
    
    result = client.cli(["show interface brief"])
    print(json.dumps(result, indent=2))
    return result


def configure_interface(client, interface, description, ipv4_address):
    """
    Configure an interface with IP address.
    
    Args:
        client: SRLinuxClient instance
        interface: Interface name (e.g., ethernet-1/1)
        description: Interface description
        ipv4_address: IPv4 address with prefix (e.g., 10.0.0.1/30)
    """
    print(f"\nConfiguring {interface}...")
    
    # Build configuration commands
    commands = [
        f"set / interface {interface} admin-state enable",
        f"set / interface {interface} description \"{description}\"",
        f"set / interface {interface} subinterface 0 admin-state enable",
        f"set / interface {interface} subinterface 0 ipv4 admin-state enable",
        f"set / interface {interface} subinterface 0 ipv4 address {ipv4_address}",
    ]
    
    # Execute in candidate datastore
    for cmd in commands:
        result = client.cli([cmd])
        print(f"  {cmd}")
    
    # Commit changes
    print("  Committing...")
    client.cli(["commit now"])
    print(f"  {interface} configured with {ipv4_address}")


def configure_bgp(client, as_number, router_id, neighbors):
    """
    Configure BGP routing.
    
    Args:
        client: SRLinuxClient instance
        as_number: Local AS number
        router_id: BGP router ID
        neighbors: List of {address, peer_as, description} dicts
    """
    print(f"\nConfiguring BGP (AS {as_number}, Router-ID {router_id})...")
    
    commands = [
        "enter candidate",
        f"set / network-instance default protocols bgp autonomous-system {as_number}",
        f"set / network-instance default protocols bgp router-id {router_id}",
        "set / network-instance default protocols bgp admin-state enable",
    ]
    
    for neighbor in neighbors:
        addr = neighbor["address"]
        peer_as = neighbor["peer_as"]
        desc = neighbor.get("description", "")
        
        commands.extend([
            f"set / network-instance default protocols bgp neighbor {addr} peer-as {peer_as}",
            f"set / network-instance default protocols bgp neighbor {addr} admin-state enable",
        ])
        if desc:
            commands.append(
                f"set / network-instance default protocols bgp neighbor {addr} description \"{desc}\""
            )
    
    commands.append("commit now")
    
    for cmd in commands:
        result = client.cli([cmd])
        print(f"  {cmd}")
    
    print("  BGP configured")


def demo_gnmi():
    """
    Demonstrate gNMI API usage (alternative to JSON-RPC).
    
    gNMI uses gRPC on port 57400 with TLS.
    Requires pygnmi library.
    """
    print("\n" + "="*50)
    print("gNMI API Example (port 57400)")
    print("="*50)
    
    try:
        from pygnmi.client import gNMIclient
        
        # gNMI connection parameters
        host = ("172.20.0.11", 57400)
        
        with gNMIclient(
            target=host,
            username="admin",
            password="NokiaSrl1!",
            insecure=True,  # Skip TLS verification in lab
            skip_verify=True
        ) as gc:
            # Get system info via gNMI
            result = gc.get(path=["/system/information"])
            print("gNMI Get /system/information:")
            print(json.dumps(result, indent=2))
            
    except ImportError:
        print("pygnmi not installed. Install with: pip install pygnmi")
    except Exception as e:
        print(f"gNMI connection failed: {e}")
        print("This may be expected if SR Linux is still booting.")


def main():
    """Main entry point."""
    
    # Load inventory to get router IPs
    try:
        with open("inventory.yml", "r") as f:
            inventory = yaml.safe_load(f)
    except FileNotFoundError:
        # Use defaults if no inventory
        inventory = None
    
    # Default to srl1
    host = "172.20.0.11"
    
    if inventory:
        hosts = inventory.get("all", {}).get("children", {}).get("routers", {}).get("hosts", {})
        if "srl1" in hosts:
            host = hosts["srl1"].get("ansible_host", host)
    
    print("="*50)
    print("SR Linux JSON-RPC API Demo")
    print("="*50)
    print(f"Target: {host}")
    print(f"Auth: admin/NokiaSrl1! (basic auth over HTTP)")
    print("")
    
    try:
        # Create client
        client = SRLinuxClient(host)
        
        # Get system info
        get_system_info(client)
        
        # Get interfaces
        get_interfaces(client)
        
        # Example: configure an interface (commented out to avoid changes)
        # configure_interface(
        #     client,
        #     interface="ethernet-1/10",
        #     description="to source host",
        #     ipv4_address="10.1.0.1/24"
        # )
        
        # Example: configure BGP (commented out to avoid changes)
        # configure_bgp(
        #     client,
        #     as_number=65001,
        #     router_id="1.1.1.1",
        #     neighbors=[
        #         {"address": "10.0.12.2", "peer_as": 65002, "description": "srl2"}
        #     ]
        # )
        
        print("\nJSON-RPC API connection successful.")
        print("Uncomment configuration examples to apply changes.")
        
    except Exception as e:
        print(f"ERROR: {e}")
        print("\nSR Linux may still be booting. Wait 60-90 seconds after lab deploy.")
        return 1
    
    # Demo gNMI as well
    demo_gnmi()
    
    return 0


if __name__ == "__main__":
    sys.exit(main())

