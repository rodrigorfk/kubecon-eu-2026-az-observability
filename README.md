## Environment setup

- Using a local kubernetes cluster provisioned via Kind(https://github.com/kubernetes-sigs/kind/)
- Create a cluster with the following topology:
  - 1 master node
  - 6 worker nodes
- The worker nodes should simulate a cluster running on an AWS cloud VPC environment, expanding 3 AZs within the same region, which means the well-known topology labels, like topology.kubernetes.io/region, topology.kubernetes.io/zone, failure-domain.beta.kubernetes.io/region, failure-domain.beta.kubernetes.io/zone should be added to each node.
- Since we have 6 worker nodes, each simulated AZ will get 2 nodes.
- The cluster should run v1.35.1, e.g, kindest/node:v1.35.1 