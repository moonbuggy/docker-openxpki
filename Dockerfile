ARG DEB_RELEASE="buster"
ARG FROM_IMAGE="moonbuggy2000/debian-slim-s6:${DEB_RELEASE}"

ARG OXPKI_VERSION="3.12.0"
ARG OXPKI_CONFIG_VERSION="v3.12"
ARG TARGET_ARCH_TAG="amd64"

ARG FETCHER_ROOT="/fetcher_root"

## get usql-static
#
FROM "moonbuggy2000/usql-static:latest-openxpki-${TARGET_ARCH_TAG}" AS usql

# ## get Oracle comonents
# FROM "${FROM_IMAGE}" AS oracle_builder

# # QEMU static binaries from pre_build
# ARG QEMU_DIR
# ARG QEMU_ARCH
# COPY _dummyfile "${QEMU_DIR}/qemu-${QEMU_ARCH}-static*" /usr/bin/

# RUN apt-get update \
	# && apt-get install -qy --no-install-recommends \
		# alien \
		# wget

# ARG FETCHER_ROOT
# WORKDIR "${FETCHER_ROOT}"

# there's no way to import the oracle-instantclient12.1-basiclite-12.1.0.2.0-1.x86_64.rpm that we need here
# RUN wget -q --no-check-certificate https://www.oracle.com/au/database/technologies/instant-client/linux-x86-64-downloads.html

# RUN alien "$(ls)"

# RUN rm -rf *.rpm


## build the image
#
FROM "${FROM_IMAGE}" AS builder

# QEMU static binaries from pre_build
ARG QEMU_DIR
ARG QEMU_ARCH
COPY _dummyfile "${QEMU_DIR}/qemu-${QEMU_ARCH}-static*" /usr/bin/

RUN printf '#!/bin/sh\nexit 0' > /usr/sbin/policy-rc.d

ARG DEB_RELEASE

RUN apt-get update \
	&& apt-get install -qy --no-install-recommends \
		apache2 \
		gettext \
		gpg \
		gpg-agent \
		less \
		libapache2-mod-fcgid \
		libapache2-mod-rpaf \
		libdbd-mariadb-perl \
		libdbd-mysql-perl \
		libdbd-odbc-perl \
		libdbd-pg-perl \
		libdbd-sqlite3-perl \
		locales \
		sqlite3 \
		wget

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
	&& dpkg-reconfigure --frontend=noninteractive locales

# components for Oracle clients
# ARG FETCHER_ROOT
# COPY --from=oracle_builder "${FETCHER_ROOT}"/*.deb .

# RUN ls -la *.deb

# RUN dpkg -i *.deb \
	# && apt-get install -f \
	# && rm -f *.deb

# # 'contrib' is required only for libdbd-oracle-perl
# RUN echo "deb http://httpredir.debian.org/debian ${DEB_RELEASE} contrib" >> /etc/apt/sources.list \
	# && apt-get update \
	# && apt-get install -qy --no-install-recommends \
		# libdbd-oracle-perl

# add openxpki repo
RUN wget -qO- "http://packages.openxpki.org/v3/debian/Release.key" | apt-key add - \
  && echo "deb http://packages.openxpki.org/v3/debian/ ${DEB_RELEASE} release" > /etc/apt/sources.list.d/openxpki.list \
	&& echo "deb http://httpredir.debian.org/debian ${DEB_RELEASE} non-free" >> /etc/apt/sources.list \
	&& apt-get update


# debian-slim blocks /usr/share/doc files during installation, add an exception for
# libopenxpki-perl as it copies config files it installs to this path to /etc during
# configuration
RUN echo "path-include /usr/share/doc/libopenxpki-perl/*" >> /etc/dpkg/dpkg.cfg.d/docker

ARG OXPKI_VERSION
RUN apt-get install -qy \
		libcrypt-libscep-perl \
		libopenxpki-perl \
		libscep \
		openxpki-i18n="${OXPKI_VERSION}" \
		openxpki-cgi-session-driver

RUN a2enmod cgid fcgid headers rewrite rpaf ssl \
	&& a2dismod status \
	&& a2dissite 000-default \
	&& a2disconf serve-cgi-bin

ARG OXPKI_CONFIG_VERSION
RUN add-contenv "OXPKI_CONFIG_VERSION=${OXPKI_CONFIG_VERSION}"

# cleanup
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# remove the static binaries
RUN rm -f "/usr/bin/qemu-${QEMU_ARCH}-static" >/dev/null 2>&1


## build the final image
#
FROM "moonbuggy2000/scratch:${TARGET_ARCH_TAG}"

COPY --from=builder / /
COPY --from=usql /usql /usr/bin/
COPY ./etc /etc

ENV	S6_BEHAVIOUR_IF_STAGE2_FAILS=2

ENTRYPOINT ["/init"]
