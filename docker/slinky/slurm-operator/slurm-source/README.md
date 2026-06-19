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
`build-control-plane-images.sh` (one directory up) builds the `slurmdbd`,
`slurmrestd`, and `login` targets; set `SLURM_VERSION` / `FLAVOR` to pick the
profile. The `slurmctld` / `slurmd` targets are not used here: the controller and
workers use the layered custom Dockerfiles built by `build-images.sh`.

To refresh or add a flavor: re-copy `docker-bake.hcl` and the relevant
`<minor>/<flavor>/` directory from the upstream repo at the desired ref and
update the ref above.
