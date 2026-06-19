# Vendored Slurm component build (slurmdbd, slurmrestd, login)

These files are copied verbatim from upstream
[SlinkyProject/containers](https://github.com/SlinkyProject/containers), so the
SlurmDBD, slurmrestd, and login (SSSD sidecar) images can be built from source
into our registry alongside the layered custom images.

- Source: `SlinkyProject/containers`, path `schedmd/slurm/`
- Pinned ref: `cea8fbea1c07c727eac653a052947724492b4eb8` (2026-06-10)
- License: Apache-2.0 (SPDX headers retained in the copied files)

Vendored version/flavor directories (matching the terraform image profiles):

- `25.11/ubuntu24.04` (the `25.11.6-ubuntu24.04` profile)
- `26.05/ubuntu24.04` (the `26.05-ubuntu24.04` profile)
- `26.05/ubuntu26.04` (the `26.05.1-ubuntu26.04` profile)

Each `<minor>/<flavor>/Dockerfile` is a single multi-stage Dockerfile that builds
every Slurm component (`slurmctld`, `slurmd`, `slurmdbd`, `slurmrestd`, `sackd`,
`login`) as separate `--target` stages; `docker-bake.hcl` defines the Bake
targets and `<minor>/<flavor>/slurm.hcl` pins the Slurm micro version.
Two scripts one directory up build from these assets; set `SLURM_VERSION` /
`FLAVOR` to pick the profile:

- `build-control-plane-images.sh` builds the deployed `slurmdbd`, `slurmrestd`,
  and `login` targets (plus the operator/webhook from a pinned clone).
- `build-base-images.sh` builds the `slurmctld`, `slurmd`, `slurmd_pyxis`, and
  `login_pyxis` targets as base images that the layered custom Dockerfiles in
  `build-images.sh` (controller, login, NVIDIA workers) then build FROM, instead
  of pulling them from `ghcr.io/slinkyproject`. The `login_pyxis` target is
  tagged `login-pyxis-base` so it does not collide with the deployed
  `login-pyxis` image that `build-images.sh` produces.

To refresh or add a flavor: re-copy `docker-bake.hcl` and the relevant
`<minor>/<flavor>/` directory from the upstream repo at the desired ref and
update the ref above.
