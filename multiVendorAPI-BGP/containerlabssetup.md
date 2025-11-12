# Containerlab Deploy Command

Bash syntax:

```bash
docker run --rm -it --privileged \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/lab \
  -w /lab \
  ghcr.io/srl-labs/clab containerlab deploy -t topology.yml \
  --reconfigure
```

Powershell syntax:

```powershell
docker run --rm -it --privileged `
  --network host `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v ${PWD}:/lab `
  -w /lab `
  ghcr.io/srl-labs/clab containerlab deploy -t topology.yml `
  --reconfigure
```

- `docker run --rm -it --privileged` - Run containerlab in a container with full permissions
- `--network host` - Use host network so containers can communicate
- `-v /var/run/docker.sock:/var/run/docker.sock` - Mount Docker socket so containerlab can create containers
- `-v $(pwd):/lab` - Mount current directory into container at /lab
- `-w /lab` - Set working directory to /lab
- `ghcr.io/srl-labs/clab` - Containerlab Docker image
- `containerlab deploy -t topology.yml` - Deploy the topology
- `--reconfigure` - Recreate containers if they already exist

# ContainerLab Destroy Command

Bash syntax:

```bash
docker run --rm -it --privileged \
  --network host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/lab \
  -w /lab \
  ghcr.io/srl-labs/clab containerlab destroy -t topology.yml
```

Powershell syntax:

```powershell
docker run --rm -it --privileged `
  --network host `
  -v /var/run/docker.sock:/var/run/docker.sock `
  -v ${PWD}:/lab `
  -w /lab `
  ghcr.io/srl-labs/clab containerlab destroy -t topology.yml
```