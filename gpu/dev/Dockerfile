# Remote development container: NEST GPU + CPU NEST 3.9, SSH, Tailscale.
#
# Built on the NEST GPU image (../Dockerfile), so build that first:
#
#   docker build gpu --build-context nestgpu=../nest-gpu-tinyhippo -t tinyhippo-nestgpu:latest
#   docker compose -f gpu/dev/compose.yml build
#
# See README.md in this directory for the access model and setup.
ARG BASE_IMAGE=tinyhippo-nestgpu:latest

# ---- CPU NEST, built against the same OS and Python as the runtime -----------
FROM ${BASE_IMAGE} AS nest-cpu

ARG NEST_VERSION=3.9
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl libgsl-dev libltdl-dev libboost-dev python3-pip \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir "cython>=3.0,<3.1"
RUN curl -fsSL "https://github.com/nest/nest-simulator/archive/refs/tags/v${NEST_VERSION}.tar.gz" \
        | tar -xz -C /tmp \
    && mkdir /tmp/nest-build && cd /tmp/nest-build \
    && cmake -DCMAKE_INSTALL_PREFIX:PATH=/opt/nest \
        -Dwith-mpi=OFF -Dwith-openmp=ON -Dwith-python=ON \
        -Dwith-gsl=ON -Dwith-ltdl=ON -Dwith-readline=OFF \
        "/tmp/nest-simulator-${NEST_VERSION}" \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/nest-build "/tmp/nest-simulator-${NEST_VERSION}"

# ---- runtime ---------------------------------------------------------------
FROM ${BASE_IMAGE}

ARG DEV_USER=max
ARG DEV_UID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg git openssh-server openssh-client \
        libgsl27 libltdl7 less nano vim htop tmux \
    && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg \
        -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
    && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list \
        -o /etc/apt/sources.list.d/tailscale.list \
    && apt-get update && apt-get install -y --no-install-recommends tailscale \
    && rm -rf /var/lib/apt/lists/*

COPY --from=nest-cpu /opt/nest /opt/nest

# Both simulators import side by side: `import nestgpu` and `import nest`.
ENV PYTHONPATH=/opt/nestgpu/lib/python3.10/site-packages:/opt/nest/lib/python3.10/site-packages
ENV NEST_INSTALL_DIR=/opt/nest
ENV NEST_DATA_DIR=/opt/nest/share/nest

RUN useradd --create-home --uid "${DEV_UID}" --shell /bin/bash "${DEV_USER}" \
    && mkdir -p /run/sshd /etc/ssh/host_keys /etc/ssh/authorized_keys

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

ENV DEV_USER=${DEV_USER}
WORKDIR /home/${DEV_USER}
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
