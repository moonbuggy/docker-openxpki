ARG DEB_RELEASE="buster"
ARG FROM_IMAGE="moonbuggy2000/debian-slim-s6:${DEB_RELEASE}"

ARG OXPKI_VERSION="3.14.4-0"
ARG OXPKI_CONFIG_VERSION="v3.12"
ARG TARGET_ARCH_TAG="amd64"

ARG USQL_BUILD="mypost"
ARG USQL_VERSION="latest"

## get usql-static
#
FROM "moonbuggy2000/usql-static:${USQL_VERSION}-${USQL_BUILD}-${TARGET_ARCH_TAG}" AS usql

## build the image
#
FROM "${FROM_IMAGE}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEB_RELEASE
ARG OXPKI_VERSION
ARG OXPKI_CONFIG_VERSION
RUN export DEBIAN_FRONTEND="noninteractive" \
	&& printf '#!/bin/sh\nexit 0' > /usr/sbin/policy-rc.d \
	&& apt-get update \
	&& apt-get install -qy --no-install-recommends \
		apache2 \
		ca-certificates \
		gettext \
		gpg \
		gpg-agent \
		less \
		libapache2-mod-fcgid \
		libapache2-mod-rpaf \
		libdbd-mariadb-perl \
		libdbd-mysql-perl \
		libdbd-pg-perl \
		locales \
		wget \
	&& echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
	&& dpkg-reconfigure --frontend=noninteractive locales \
	&& wget -qO- "http://packages.openxpki.org/v3/debian/Release.key" | apt-key add - 2>/dev/null \
  && echo "deb http://packages.openxpki.org/v3/debian/ ${DEB_RELEASE} release" > /etc/apt/sources.list.d/openxpki.list \
	&& echo "deb http://httpredir.debian.org/debian ${DEB_RELEASE} non-free" >> /etc/apt/sources.list \
	&& apt-get update \
	# debian-slim blocks /usr/share/doc files during installation, add an exception for \
	# libopenxpki-perl as it copies config files it installs to this path to /etc during \
	# configuration \
#	&& echo "path-include /usr/share/doc/libopenxpki-perl/*" >> /etc/dpkg/dpkg.cfg.d/docker \
	&& echo "path-include /usr/share/doc/libopenxpki-perl/examples/*" >> /etc/dpkg/dpkg.cfg.d/docker \
	# but sometimes the OpenXPKI repo packages don't install a file we need (or \
	# install a *.gz then have the gunzipped file as a dependency), so we can pull \
	# from GitHub in those cases \
	&& mkdir -p /usr/share/doc/libopenxpki-perl/examples/ \
	&& wget -qO '/usr/share/doc/libopenxpki-perl/examples/apache2-openxpki-site.conf' \
		'https://raw.githubusercontent.com/openxpki/openxpki-config/community/contrib/apache2-openxpki-site.conf' \
	&& apt-get install -qy --no-install-recommends \
		libcrypt-libscep-perl \
		libopenxpki-perl \
		libscep \
		openxpki-i18n="${OXPKI_VERSION}" \
		openxpki-cgi-session-driver="${OXPKI_VERSION}" \
	# openxpki-i18n doesn't install properly from the repo, do it manually if necessary \
	&& if [ ! -f '/usr/share/locale/en_US/LC_MESSAGES/openxpki.mo' ]; then \
		tempdir="$(mktemp -d)"; \
		wget -qO i18n.deb \
			"http://packages.openxpki.org/v3/debian/pool/release/o/openxpki-i18n/openxpki-i18n_${OXPKI_VERSION}_amd64.deb"; \
		dpkg-deb -R i18n.deb "${tempdir}"; \
		cp -r "${tempdir}/usr/share/locale" '/usr/share/'; \
		rm -f i18n.deb; \
		rm -rf "${tempdir}"; fi \
	&& add-contenv \
		"OXPKI_VERSION=${OXPKI_VERSION}" \
		"OXPKI_CONFIG_VERSION=${OXPKI_CONFIG_VERSION}" \
	# cleanup install \
	&& apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
	# configure apache \
	&& a2enmod -q cgid fcgid headers rewrite rpaf ssl \
	&& a2dismod -q status \
	&& a2dissite -q 000-default \
	&& a2disconf -q serve-cgi-bin

COPY --from=usql /usql /usr/bin/
COPY ./etc /etc

ENV	S6_BEHAVIOUR_IF_STAGE2_FAILS=2

ENTRYPOINT ["/init"]
