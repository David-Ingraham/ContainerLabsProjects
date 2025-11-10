# Network Link Creation Script - Detailed Explanation

## What This Script Does

Creates virtual network cables (veth pairs) between Docker containers to connect them as defined in your topology.

## Bash Syntax Explained

### Shebang and Options

```bash
#!/bin/bash
```
- `#!` = shebang - tells the system "use bash to run this"
- `/bin/bash` = path to the bash interpreter

```bash
set -e
```
- `set` = configure shell behavior
- `-e` = exit immediately if any command fails (non-zero exit code)
- Without this, script would continue even after errors

### Variables

```bash
local c1_name="$1"
```
- `local` = variable only exists inside this function (not global)
- `c1_name` = variable name
- `=` = assignment operator (no spaces allowed around =)
- `"$1"` = first argument passed to the function
  - `$1`, `$2`, `$3`, etc. are positional parameters
  - Quotes prevent word splitting if value has spaces

```bash
local c1_pid=$(docker inspect -f '{{.State.Pid}}' "$c1_name")
```
- `$()` = command substitution - runs command and replaces with output
- `docker inspect` = get detailed info about container
- `-f` = format flag
- `'{{.State.Pid}}'` = Go template to extract just the PID field
- Result: assigns container's PID to variable

### Conditionals

```bash
if [ -z "$c1_pid" ] || [ "$c1_pid" = "0" ]; then
    echo "ERROR"
    return 1
fi
```
- `if` ... `then` ... `fi` = if statement
- `[ ]` = test command (checks conditions)
- `-z "$c1_pid"` = true if string is empty (zero length)
- `||` = logical OR
- `=` = string equality test
- `"0"` = Docker returns PID 0 if container stopped
- `return 1` = exit function with error code 1
- `fi` = end if statement (if backwards)

### String Manipulation

```bash
local veth_a="v${c1_name: -3}${c2_name: -3}a"
```
- `${c1_name: -3}` = substring extraction
  - `:` = substring operator
  - `-3` = last 3 characters (negative index from end)
  - Example: `"clab-multi-vendor-api-bgp-client1"` → `"nt1"`
- Linux interface names limited to 15 characters
- Format: `v` + last3chars_container1 + last3chars_container2 + `a`/`b`
- Example: `vnt1rr1a` (8 chars total)

## Docker/Networking Concepts

### Container PIDs

```bash
docker inspect -f '{{.State.Pid}}' "$c1_name"
```

**Why we need PID:**
- Every container is a Linux process with a Process ID (PID)
- Containers use Linux namespaces for isolation
- Network namespace = isolated network stack (interfaces, routes, IPs)
- We access namespace via `/proc/<PID>/ns/net`

### veth Pairs

```bash
ip link add "$veth_a" type veth peer name "$veth_b"
```

**What is a veth pair?**
- Virtual Ethernet pair = two connected network interfaces
- Like a virtual cable with two ends
- Packet sent to veth_a appears at veth_b (and vice versa)
- Used to connect network namespaces

**Command breakdown:**
- `ip link add` = create a network interface
- `"$veth_a"` = name of first end
- `type veth` = specify it's a virtual ethernet pair
- `peer name "$veth_b"` = name of the other end
- Requires root privileges (script runs in privileged container)

### Moving to Namespaces

```bash
ip link set "$veth_a" netns "$c1_pid"
```

**What happens:**
- Moves veth_a from host namespace into container's namespace
- `ip link set` = modify network interface
- `netns "$c1_pid"` = target namespace identified by PID
- After this, veth_a disappears from host, appears in container

### nsenter Command

```bash
nsenter -t "$c1_pid" -n ip link set "$veth_a" name "$c1_iface"
```

**What is nsenter?**
- "namespace enter" - run command inside another namespace
- `-t "$c1_pid"` = target process PID
- `-n` = enter network namespace
- Remaining args = command to run inside namespace
- Like doing `docker exec` but at the namespace level

**Why not docker exec?**
- We need to run commands before container is fully ready
- nsenter is lower-level, works with any process namespace
- More reliable for network setup

### Bringing Interfaces Up

```bash
nsenter -t "$c1_pid" -n ip link set "$c1_iface" up
```

**Why needed:**
- Network interfaces start in "DOWN" state (disabled)
- `ip link set <iface> up` = enable the interface
- DOWN interfaces don't pass traffic
- Like plugging in a cable but not turning on the port

## Function Definition

```bash
create_link() {
    local c1_name="$1"
    # ... function body ...
}
```

**Bash function syntax:**
- `function_name() { }` = define function
- No parameter list in definition
- Access parameters via `$1`, `$2`, etc. inside function
- `local` variables exist only within function

## Calling the Function

```bash
create_link "$CLIENT1" "eth1" "$FRR1" "eth1"
```

**How arguments map:**
- `"$CLIENT1"` → `$1` (c1_name)
- `"eth1"` → `$2` (c1_iface)
- `"$FRR1"` → `$3` (c2_name)
- `"eth1"` → `$4` (c2_iface)

## Running the Script

### macOS with Docker Desktop

macOS doesn't have Linux `ip` command or direct access to Docker's Linux VM. Must run script inside a privileged container:

```bash
# From project directory
docker run --rm -it --privileged \
  --pid=host \
  --network=host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd)/create-links.sh:/create-links.sh \
  alpine sh
```

**Inside the Alpine container:**
```bash
# Install required tools
apk add iproute2 docker-cli

# Run the script
sh /create-links.sh
```

**Why this approach:**
- Script needs Linux `ip` command (not available on macOS)
- Needs access to Docker VM's process namespaces
- `--pid=host` gives access to all container PIDs
- `--privileged` grants network namespace manipulation rights
- Already running as root in container (no sudo needed)

### Linux with Native Docker

```bash
sudo ./create-links.sh
```

## Verification

```bash
docker exec clab-multi-vendor-api-bgp-client1 ip addr
```

Should show:
- `lo` - loopback
- `eth0` - management (172.20.20.x)
- `eth1` - topology link (state UP)

## Troubleshooting

### Issue: Containerlab Race Condition on macOS

**Symptom:**
```
ERRO failed deploy links for node "client1": failed to Statfs "/proc/3858/ns/net": no such file or directory
```

**Root cause:**
- Containerlab runs in Docker container on macOS
- Attempts to access container network namespace immediately after creation
- Docker Desktop adds latency (macOS → Docker VM → containerlab → containers)
- Process namespace file doesn't exist yet when containerlab tries to read it

**Why --max-workers 1 doesn't help:**
- Even sequential creation has timing issues
- Each container needs ~1-2 seconds to fully initialize namespace
- Containerlab doesn't wait for namespace readiness

**Solution:**
Manual link creation via this script after containers are running.

### Issue: Interface Name Too Long

**Symptom:**
```
Error: argument "veth_ent1_frr1_b" is wrong: "name" not a valid ifname
```

**Root cause:**
- Linux limits interface names to 15 characters
- Original naming: `veth_ent1_frr1_b` = 17 chars

**Solution:**
- Shortened to `v${c1_name: -3}${c2_name: -3}a` format
- Example: `vnt1rr1a` = 8 chars

### Issue: Commands Not Found in Alpine

**Symptom:**
```
/create-links.sh: line 44: ip: command not found
/create-links.sh: line 22: docker: not found
```

**Root cause:**
- Alpine Linux is minimal (5MB base image)
- Doesn't include networking tools or Docker CLI by default

**Solution:**
```bash
apk add iproute2 docker-cli
```

### Issue: sudo Not Found in Container

**Symptom:**
```
/create-links.sh: line 44: sudo: not found
```

**Root cause:**
- Script originally written for macOS host execution
- Alpine doesn't include sudo by default
- Already running as root in privileged container

**Solution:**
Removed all `sudo` from script (unnecessary when running as root).

