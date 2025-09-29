# Flower Deployment Quickstart for Thunderline Clusters

This folder captures a Kubernetes baseline that mirrors the [Flower Docker "Quickstart" topology](https://flower.ai/docs/framework/docker/tutorial-quickstart-docker.html) (SuperLink + SuperNodes + SuperExec) so we can run the Thunderline federated learning demo inside the same cluster.

## What lives here?

- `flower-quickstart.yaml` – a manifest bundle that stands up the Flower control plane components:
  - `Namespace` (`flower-system`)
  - `SuperLink` Deployment + Service (`flwr/superlink:1.22.0`)
  - Two `SuperNode` Deployments + Services (`flwr/supernode:1.22.0`, partition ids 0 and 1)
  - Three `SuperExec` Deployments wired for one ServerApp worker and two ClientApp workers (pointing at the SuperNodes)
- `superexec.Dockerfile` – build recipe for producing the `flower-superexec` image that bakes in your Flower app (ServerApp + ClientApp code). The YAML above references `ghcr.io/thunderblok/flower-superexec:0.0.1`; retag to match wherever you publish the image.

The manifests are intentionally vanilla so they can be dropped into existing GitOps tooling (Flux/Argo) or applied ad-hoc while we iterate.

## Deploying the Flower topology

1. **Create/build your Flower application** (one repo can host both the server and clients):

   ```bash
   flwr new thunderline-demo --framework PyTorch --username thunderline
   cd thunderline-demo
   pip install -e .
   # run locally with `flwr run . local-deployment --stream` if desired
   ```

2. **Bake the SuperExec image** so the runtime has access to your Flower app code. From the root of your Flower project:

   ```bash
   docker build \
     -f /path/to/Thunderline/ops/federation/flower/superexec.Dockerfile \
     --build-arg APP_SRC=. \
     -t ghcr.io/thunderblok/flower-superexec:0.0.1 .

   docker push ghcr.io/thunderblok/flower-superexec:0.0.1
   ```

   Adjust the tag/registry to match your infra. The Dockerfile copies the project into `/workspace/app` and strips any duplicate `flwr[...]` dependency before installing the remaining Python requirements (Flower ships inside the base image already).

3. **Create the Flower namespace in your cluster**:

   ```bash
   kubectl create namespace flower-system
   ```

4. **Apply the manifest bundle**:

   ```bash
   kubectl apply -n flower-system -f ops/federation/flower/flower-quickstart.yaml
   ```

   Confirm everything is up:

   ```bash
   kubectl get pods -n flower-system
   kubectl get svc  -n flower-system
   ```

   You should see the `flower-superlink`, `flower-supernode-{0,1}` and `flower-superexec-*` workloads running. The SuperLink exposes ports 9091/9092/9093 via the internal service `flower-superlink`. Each SuperNode exposes its ClientAppIO port (`flower-supernode-0:9094`, `flower-supernode-1:9095`).

5. **Wire Thunderline to the Flower services** by pointing the federation configs (Helm values or env vars) at the in-cluster DNS entries above. The Thunderline control plane will publish federated jobs to the SuperLink endpoint and register clients against the SuperNode services.

6. **Tear down** when done:

   ```bash
   kubectl delete -n flower-system -f ops/federation/flower/flower-quickstart.yaml
   kubectl delete namespace flower-system
   ```

## Hardening & Production TODO

- Swap the demo image references for hardened, pinned versions maintained in our registry (enable image signing).
- Layer NetworkPolicies so only Thunderline pods can reach the Flower services (and vice-versa).
- Add PodDisruptionBudgets and liveness/readiness probes.
- Externalize secrets/certs for TLS + authentication (Flower supports mTLS and user auth, see docs linked above).
- Expand node selectors/tolerations to target GPU pools when we roll out accelerated clients.

## Alternatives to Flower

If we decide Flower’s Deployment Engine isn’t the right fit, the closest drop-in alternatives are:

- **FedML/FedML Launch** – heavier (focuses on edge + cloud orchestration) but comes with its own control plane; we’d need custom adapters for Thunderline events.
- **OpenFL** – Intel-backed, leans on TLS attestation + SGX. Great for regulated deployments but significantly more invasive to integrate.
- **Ray AIR Federated** – if we double-down on Ray for distributed inference, we could reuse AIR’s federated primitives; still alpha compared to Flower’s maturity.

For now Flower remains the most ergonomic option with strong community support, and the layout above keeps it close to the upstream quickstart so their docs stay applicable.
