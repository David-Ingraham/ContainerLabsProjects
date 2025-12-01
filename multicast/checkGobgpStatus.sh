docker exec -it clab-bgp-lab-gobgp1 gobgp neighbor
docker exec -it clab-bgp-lab-gobgp1 gobgp global rib
docker exec -it clab-bgp-lab-gobgp1 gobgp neighbor 10.0.1.2 adj-in
docker exec -it clab-bgp-lab-gobgp1 gobgp neighbor 10.0.1.2 adj-out
