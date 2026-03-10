################################################################################
#                        Install dependencies for dev                          #
################################################################################

ARG fromImage=ubuntu:24.04
FROM ${fromImage} AS dev

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Los_Angeles
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

ARG INSTALLER_ARGS=""

WORKDIR /tmp

COPY etc/DependencyInstaller.sh .

RUN chmod +x DependencyInstaller.sh && \
    ./DependencyInstaller.sh -ci -base && \
    ./DependencyInstaller.sh -ci -common \
    -save-deps-prefixes=/etc/openroad_deps_prefixes.txt \
    $INSTALLER_ARGS && \
    if echo "${fromImage}" | grep -q "ubuntu"; then \
    strip --remove-section=.note.ABI-tag \
    /usr/lib/x86_64-linux-gnu/libQt5Core.so || true; \
    fi && \
    rm DependencyInstaller.sh

################################################################################
#                         Build OpenROAD from source                           #
################################################################################

FROM dev AS builder

ARG compiler=gcc
ARG numThreads=0
ARG orVersion=dev

RUN groupadd -g 9000 user && \
    useradd -m -u 9000 -g user -s /bin/bash user

USER user
WORKDIR /OpenROAD

COPY --chown=user:user . .

RUN if [ -f /opt/rh/gcc-toolset-13/enable ]; then \
    . /opt/rh/gcc-toolset-13/enable; \
    fi && \
    DEPS_ARGS="" && \
    if [ -f /etc/openroad_deps_prefixes.txt ]; then \
    DEPS_ARGS=$(cat /etc/openroad_deps_prefixes.txt); \
    fi && \
    cmake -B build -S . \
    -DCMAKE_BUILD_TYPE=Release \
    -DOPENROAD_VERSION="${orVersion}" \
    $DEPS_ARGS && \
    if [ "$numThreads" = "0" ]; then \
    numThreads=$(nproc); \
    fi && \
    cmake --build build -j${numThreads}

################################################################################
#                              Final runtime image                             #
################################################################################

FROM dev AS final

RUN groupadd -g 9000 user && \
    useradd -m -u 9000 -g user -s /bin/bash user

COPY --from=builder /OpenROAD/build/bin/openroad /usr/bin/openroad
COPY --chmod=755 --chown=user:user etc/docker-entrypoint.sh /usr/local/bin/

ENV OPENROAD_EXE=/usr/bin/openroad

USER user
WORKDIR /home/user

ENTRYPOINT ["openroad"]
