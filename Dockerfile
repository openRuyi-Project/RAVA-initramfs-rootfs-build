# syntax = docker/dockerfile:1.1-experimental
ARG BASE_IMAGE                                                                                                                                                                                                                                                                                                           
FROM $BASE_IMAGE  

# use fast mirror (only for openEuler)
RUN if [ -f /etc/yum.repos.d/openEuler.repo ]; then \
    sed -i 's|repo.openeuler.org|fast-mirror.isrc.ac.cn/openeuler|g' /etc/yum.repos.d/openEuler.repo; \
    sed -i 's|^metalink=|#metalink=|g' /etc/yum.repos.d/openEuler.repo; \
    fi

# use fast mirror for openruyi
RUN if [ -f /etc/yum.repos.d/openruyi.repo ]; then \
    sed -i 's|https://repo.build.openruyi.cn/openruyi/|https://boat.openruyi.cn/unstable/|g' /etc/yum.repos.d/openruyi.repo; \
    fi

# install packages
RUN dnf makecache && \
    dnf install -y wget xz shadow dracut rsync git gpg tar ca-certificates zstd e2fsprogs util-linux && \
    dnf clean all

# create result dir
RUN mkdir /srv/initramfs_result

# copy script
COPY initramfs-build /usr/bin/initramfs-build
RUN chmod +x /usr/bin/initramfs-build
