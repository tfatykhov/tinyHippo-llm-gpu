# Remote GPU dev container

A Linux container on the GPU workstation that a remote collaborator reaches over Tailscale with SSH. It has
NEST GPU (the project build, `../README.md`), CPU NEST 3.9, the Python stack, git and the usual shell tools.

## Access model

| | |
|---|---|
| Network | The container runs Tailscale itself (userspace mode) and joins the tailnet as its own machine, `tinyhippo-gpu`. It publishes no ports, and the Windows host needs no Tailscale and opens nothing. Tailscale's control socket is root-only, so the dev user cannot use the container to reach other devices on the tailnet. |
| Who can reach it | Whoever the node is shared with (Tailscale node sharing): they reach this one machine, not the host or the rest of the tailnet. |
| Login | SSH with public keys only, one account (`max` by default), no root login. Keys come from `secrets/authorized_keys` on the host, installed root-owned at every container start, so they cannot be changed from inside. |
| Files | No host directory is mounted and there is no Docker socket. The user works in their home directory, a named volume, and moves code with git. |
| GPU | The whole RTX 4060 Ti (16 GB), shared with the host's display and with anything else running on it. |

What this protects: the host's files, its other containers (databases, other projects), and the rest of the
tailnet. What it does not: the container itself, its GPU time, and outbound internet from it. Treat it as a
shared workstation account, not a sandbox for untrusted code.

Tested on 2026-10-24 and 2026-10-25: key-only SSH as `max`, GPU and both simulators in a non-login SSH
session, a model run on each simulator, and that the home directory and host key survive a recreate. On a
real tailnet: the node joins, comes back from its saved state after a restart or a recreate with
`TS_AUTHKEY` removed, accepts a key login on its tailnet address (dialled from inside the node), refuses a
wrong key, and the dev user cannot reach other tailnet devices. Not yet tested: a login from another
machine. Max's first login (step 5) is that test.

## Setup on the workstation (once)

1. Build the NEST GPU image (`../README.md`), then this one:
   ```sh
   docker compose -f gpu/dev/compose.yml build
   ```
   CPU NEST compiles in the first build.
2. Authorised keys. Create `gpu/dev/secrets/authorized_keys` before the first start (otherwise Docker
   creates a directory there). One public key per line, e.g. Max's after confirming with him which one:
   ```sh
   mkdir -p gpu/dev/secrets
   curl -fsSL https://github.com/max-talanov.keys > gpu/dev/secrets/authorized_keys
   ```
   Or generate a dedicated pair here and send the private half to Max over a private channel (he can add a
   passphrase with `ssh-keygen -p`); delete your copy once he has logged in:
   ```sh
   ssh-keygen -t ed25519 -N "" -C max@tinyhippo-gpu -f gpu/dev/secrets/max_tinyhippo_ed25519
   cp gpu/dev/secrets/max_tinyhippo_ed25519.pub gpu/dev/secrets/authorized_keys
   ```
   Add your own key on another line if you want to log in too.
3. Tailscale. In the admin console, create an auth key (Settings > Keys): reusable, tagged (for example
   `tag:tinyhippo`, declared in the ACL policy's `tagOwners`). Copy `.env.example` to `.env` and set
   `TS_AUTHKEY`. After the first login the node state lives in the `tailscale` volume, so remove the key from
   `.env`; the node comes back from its saved state on restart. A key from the console's "Add device" page
   also works, but the node then belongs to your user and its node key expires (180 days by default;
   Machines > `tinyhippo-gpu` > Disable key expiry).
4. Start it:
   ```sh
   docker compose -f gpu/dev/compose.yml up -d
   docker compose -f gpu/dev/compose.yml logs dev     # sshd and Tailscale status
   ```
5. Share the node: admin console > Machines > `tinyhippo-gpu` > Share, and send Max the invite. He accepts it
   in his own (free) Tailscale account. Then have him run `tailscale ping tinyhippo-gpu` followed by
   `ssh max@tinyhippo-gpu`. If the ping works but SSH is refused or times out, your ACL policy is not
   letting shared users reach port 22 on this node; if SSH says "Permission denied (publickey)", the key in
   `secrets/authorized_keys` is not the one he is using.
6. Keep it reachable: Docker Desktop runs only while you are signed in to Windows. Disable sleep, let Docker
   Desktop start at sign-in, and expect an outage after a Windows Update reboot until you sign in again. The
   container restarts on its own (`restart: unless-stopped`).

Optional hardening in the tailnet ACL policy: allow only port 22 to `tag:tinyhippo`.

## For the remote user

```sh
ssh max@tinyhippo-gpu        # MagicDNS name; or the 100.x address shown in Tailscale
```

The first connection shows the host key fingerprint; it stays the same across container rebuilds.

```sh
git clone https://github.com/max-talanov/tinyHippo-llm-gpu.git && cd tinyHippo-llm-gpu
nvidia-smi                                         # check whether someone else is using the GPU
python3 gpu_spike/izh_het_check.py                 # NEST GPU (`import nestgpu`)
python3 replay_scaled.py --scale 1 --n-swr 1 --no-figures --threads 8   # CPU NEST (`import nest`)
```

- VS Code Remote-SSH works with the same host name.
- `tmux` keeps long runs alive after you disconnect.
- Your home directory persists across container restarts and rebuilds. Python packages go in with
  `pip install --user`; there is no root access.
- The GPU is shared: check `nvidia-smi` before starting long runs, and keep 12% runs (about 2 GB of GPU
  memory) to one at a time unless agreed.

## Stopping access

| | |
|---|---|
| Pause | `docker compose -f gpu/dev/compose.yml stop` |
| Revoke one person | Remove their key from `secrets/authorized_keys` and restart (`docker compose -f gpu/dev/compose.yml restart`), or unshare the node in Tailscale |
| Remove everything | `docker compose -f gpu/dev/compose.yml down -v`, which deletes the volumes, including the home directory |
