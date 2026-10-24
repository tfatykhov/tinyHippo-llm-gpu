#!/bin/bash
# Start sshd and (if TS_AUTHKEY is set or the node was logged in before)
# Tailscale in userspace mode, then stay in the foreground.
set -euo pipefail

DEV_USER="${DEV_USER:-max}"
TS_HOSTNAME="${TS_HOSTNAME:-tinyhippo-gpu}"

# SSH sessions start with a clean environment, not the container's. Copy the
# variables that make CUDA, NEST GPU and CPU NEST work into /etc/environment,
# which sshd's PAM applies to every session, including `ssh host command`
# (a non-login shell that never reads /etc/profile.d). Whitelisted by name, so
# secrets such as TS_AUTHKEY never land in it; none of these values has spaces.
env | grep -E '^(PATH|LD_LIBRARY_PATH|LIBRARY_PATH|CUDA_VERSION|NVIDIA_VISIBLE_DEVICES|NVIDIA_DRIVER_CAPABILITIES|NESTGPU_[A-Z_]+|NEST_[A-Z_]+|PYTHONPATH|PYTHONUNBUFFERED|MPLBACKEND)=' \
    > /etc/environment
chmod 0644 /etc/environment

# Host keys persist in a volume, so the fingerprint survives container rebuilds.
for t in ed25519 rsa; do
    f="/etc/ssh/host_keys/ssh_host_${t}_key"
    [ -f "$f" ] || ssh-keygen -q -t "$t" -N "" -f "$f"
done

# Authorised keys come from a staged mount; install them root-owned so sshd
# accepts them and the user cannot change them. Re-read on every start.
install -m 0644 -o root -g root /dev/null "/etc/ssh/authorized_keys/${DEV_USER}"
if [ -f /run/secrets/authorized_keys ]; then
    tr -d '\r' < /run/secrets/authorized_keys > "/etc/ssh/authorized_keys/${DEV_USER}"
fi
if [ ! -s "/etc/ssh/authorized_keys/${DEV_USER}" ]; then
    echo "[entrypoint] WARNING: no authorised keys (secrets/authorized_keys missing or empty); nobody can log in" >&2
else
    echo "[entrypoint] $(grep -c . "/etc/ssh/authorized_keys/${DEV_USER}") authorised key(s) for ${DEV_USER}"
fi

# The home directory is a named volume; give it to the user on first start.
if [ "$(stat -c %U "/home/${DEV_USER}")" != "${DEV_USER}" ]; then
    chown -R "${DEV_USER}:${DEV_USER}" "/home/${DEV_USER}"
fi

grep -q "^AllowUsers " /etc/ssh/sshd_config || echo "AllowUsers ${DEV_USER}" >> /etc/ssh/sshd_config
/usr/sbin/sshd -t
/usr/sbin/sshd
echo "[entrypoint] sshd listening on port 22 (container network only; no published ports)"

# Tailscale in userspace mode needs no /dev/net/tun and no extra capabilities.
# Incoming tailnet connections are forwarded to local ports (here, sshd).
mkdir -p /var/run/tailscale /var/lib/tailscale
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state \
    --socket=/var/run/tailscale/tailscaled.sock >/var/log/tailscaled.log 2>&1 &
for _ in $(seq 1 50); do
    tailscale status >/dev/null 2>&1 && break
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 0.2
done

if [ -n "${TS_AUTHKEY:-}" ]; then
    # A failed login must not kill the container (restart loop); report it.
    tailscale up --authkey="${TS_AUTHKEY}" --hostname="${TS_HOSTNAME}" --accept-dns=false \
        || echo "[entrypoint] ERROR: tailscale up failed; see /var/log/tailscaled.log" >&2
elif tailscale status >/dev/null 2>&1; then
    echo "[entrypoint] Tailscale: using the saved node state"
else
    echo "[entrypoint] Tailscale: not logged in (set TS_AUTHKEY in .env to join the tailnet)"
fi
tailscale status 2>&1 | head -5 || true

# Stay in the foreground; stop cleanly on docker stop.
trap 'tailscale down >/dev/null 2>&1 || true; exit 0' TERM INT
sleep infinity &
wait $!
