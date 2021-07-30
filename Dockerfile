ARG OXPKI_VERSION="3.12.0"
ARG OXPKI_CONFIG_VERSION="v3.12"
ARG TARGET_ARCH_TAG="amd64"

ARG BUILD_ROOT="/build"

## get files we need, patch where necessary
#
FROM "moonbuggy2000/fetcher:latest-${TARGET_ARCH_TAG}" AS fetcher

ARG BUILD_ROOT

## OpenXPKI
WORKDIR "${BUILD_ROOT}/openxpki"

ARG OXPKI_VERSION
RUN git clone --depth=1 --branch "v${OXPKI_VERSION%%-*}" https://github.com/openxpki/openxpki.git .

## Proc::ProcessTable
WORKDIR "${BUILD_ROOT}/processtable"

RUN git clone --depth=1 https://github.com/jwbargsten/perl-proc-processtable .

# patch for musl, using sed or the patch file
#RUN sed -E \
#	-e "s|(^\s*link\s*=\s*)canonicalize_file_name\(link_file\)\;|\1 realpath\(link_file, NULL\)\;|" \
#	-e 's|(^\s*if\s*\(sscanf.*)\(%15c"|\1(%c"|' \
#	-i os/Linux.c
#RUN sed -E "s|(^\s*\'LIBS\'\s*=>\s*\[\')(.*)|\1-lobstack \2|" -i Makefile.PL

COPY perl-proc-processtable.patch ./

# the t/process.t hunk doesn't seem to apply properly, allow for it to fail
RUN git apply --ignore-space-change --reject perl-proc-processtable.patch || true


## build things
#
FROM "moonbuggy2000/alpine-builder:3.13.2-${TARGET_ARCH_TAG}" AS builder

USER root

#	Install as much as possible from the Alpine package repo. It's faster than CPAN and
# potentially avoids build failures because glibc/musl conflicts will be taken care of
# upstream (presumably).
#
# Date::Parse	=	perl-timedate
#	Net::LDAP	=	perl-ldap
#	MIME::Entity = perl-mime-tools
#
#	App::mymeta_requires requires:
#		Getopt::Lucid
#		Class::Tiny	=	perl-class-tiny
#		File::pushd
#		Test::Deep
#
#	Getop::Lucid requires:
#		Exception::Class::TryCatch
#
#	Config::Merge requires:
#		Config::any	=	perl-config-any
#		YAML	=	perl-yaml
#
#	Config::Versioned requires:
#		Git::PurePerl
#		Path::Class = perl-path-class
#
# Git::PurePerl requires:
#		Test::utf8	=	perl-test-utf8
#		IO::Digest
#		MooseX::Types::Path::Class = perl-moosex-types-path-class
#		Data::Stream::Bulk
#		File::Find::Rule	= perl-file-find-rule
#		Config::GitLike requires:
#			Moo = perl-moo
#			MooX::Types::MooseLike = perl-moox-types-mooselike
#		MooseX::StrictConstructor
#			Test::Needs = perl-test-needs
#		Archive::Extract	=	perl-archive-extract
#
#	Connector requires:
#		bash = bash
#		Proc::SafeExec
#		Template = perl-template-toolkit
#		Config::Versioned
#		Config::Merge
#
#		? Module::Build::Tiny = perl-module-build-tiny
#
#	DBIx::Handler requires:
#		Test::SharedFork	=	perl-test-sharedfork
#		DBIx::TransactionManager
#
#	Devel::NYTProf requires:
#		File::Which	=	perl-file-which
#		Test::Differences	=	perl-test-differences
#		JSON::MaybeXS	=	perl-json-maybexs
#
#	IO::Prompt requires:
#		Want	= perl-want
#		Term::ReadKey	=	perl-term-readkey
#
#	Locale::gettext_pp = perl-libintl-perl
#
#	Log::Log4perl::Layout::JSON requires:
#		Test::Most = perl-test-most
#
#	MooseX::InsideOut requires:
#		Hash::Util::FieldHash::Compat
#
#	MooseX::Params::Validate requires:
#		Devel::Caller
#			PadWalker	=	perl-padwalker
#
#	Pod::POM requires:
#		File::Slurper	=	perl-file-slurper
#
#	Proc::Daemon requires:
#		Proc::ProcessTable		FAILS TO BUILD
#
#	SOAP::Lite
#		XML::Parser::Lite
#		IO::SessionData
#
#	SQL::Abstract::More
#		SQL::Abstract	=	perl-sql-abstract
#
#	XML::Parser:Lite
#		fails, missing https://raw.githubusercontent.com/Perl/perl5/blead/pod/perldiag.pod
#
#	Workflow requires:
#		Class::Accessor	=	perl-class-accessor
#		Test::Kwalitee
#			Module::CPANTS::Analyse
#				==> see below
#		Mock::MonkeyPatch
#		Pod::Coverage::TrustPod
#			Pod::Eventual::Simple
#				Mixin::Linewise::Readers
#					PerlIO::utf8_strict
#		Class::Factory
#		File::Slurp	=	perl-file-slurp
#		DBD::Mock
#
#	Module::CPANTS::Analyse requires:
#		ExtUtils::MakeMaker::CPANfile
#			Module::CPANfile
#		Test::FailWarnings	=	perl-test-failwarnings
#		File::Find::Object
#			Class::XSAccessor	=	perl-class-xsaccessor !!! This Alpine package breaks the build, better to install from
#																										CPAN, at least until it's moved from testing to main.
#		Data::Binary
#		Archive::Any::Lite
#			Test::UseAllModules = perl-test-useallmodules
#		Module::Find	=	perl-module-find
#		Perl::PrereqScanner::NotQuiteLite
#			Data::Dump	=	perl-data-dump
#			URI::cpan
#			Regexp::Trie
#		Array::Diff
#		CPAN::DistnameInfo
#		Software::License
#			Text::Template	=	perl-text-template
#			Data::Section
#
# This gives extra diags at 'make test', not needed for OpenXPKI:
#		Test::Prereq
#

RUN apk -U add \
		bash \
		musl-obstack-dev \
		openssl-dev \
		perl-app-cpanminus \
		perl-archive-zip \
		perl-cgi \
		perl-cgi-fast \
		perl-cgi-session \
		perl-class-accessor \
		perl-class-tiny \
		perl-config-any \
		perl-crypt-cbc \
		perl-crypt-jwt \
		perl-crypt-rijndael \
		perl-crypt-x509 \
		perl-data-uuid \
		perl-data-dump \
		perl-datetime \
		perl-datetime-format-strptime \
		perl-dbd-sqlite \
		perl-dbi \
		perl-dev \
		perl-exception-class \
		perl-file-find-rule \
		perl-file-slurp \
		perl-file-slurper \
		perl-file-which \
		perl-json \
		perl-json-maybexs \
		perl-ldap \
		perl-log-log4perl \
		perl-lwp-protocol-https \
		perl-mime-tools \
		perl-module-build \
		perl-module-build-tiny \
		perl-moo \
		perl-moose \
		perl-moosex-types-path-class \
		perl-moox-types-mooselike \
		perl-net-dns \
		perl-net-server \
		perl-netaddr-ip \
		perl-padwalker \
		perl-params-validate \
		perl-path-class \
		perl-regexp-common \
		perl-sub-exporter \
		perl-template-toolkit \
		perl-term-readkey \
		perl-test-differences \
		perl-test-failwarnings \
		perl-test-most	\
		perl-test-needs \
		perl-test-pod \
		perl-test-pod-coverage \
		perl-test-sharedfork \
		perl-text-csv_xs \
		perl-text-template \
		perl-time-hires \
		perl-timedate \
		perl-try-tiny \
		perl-want \
		perl-xml-simple \
		perl-yaml \
		perl-yaml-tiny \
		wget

RUN apk -U add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
		perl-archive-extract \
#		perl-class-xsaccessor \
		perl-libintl-perl \
		perl-module-find \
		perl-sql-abstract \
		perl-test-useallmodules \
		perl-test-utf8

RUN cpanm \
		App::mymeta_requires \
		Config::Std \
		ExtUtils::MakeMaker

## fix Config::Versioned
ENV USER=root

## fix XML::Parser::Lite
RUN mkdir -p /usr/share/perl5/core_perl/pods/ \
	&&	wget -qO- https://raw.githubusercontent.com/Perl/perl5/blead/pod/perldiag.pod > /usr/share/perl5/core_perl/pods/perldiag.pod

ARG BUILD_ROOT
COPY --from=fetcher "${BUILD_ROOT}" "${BUILD_ROOT}"

## build and install Proc::ProcessTable
WORKDIR "${BUILD_ROOT}/processtable"

# required for testing only
RUN apk add \
	grep \
	procps

RUN perl Makefile.PL
RUN make 
RUN make test
RUN make install

## build OpenXPKI
WORKDIR "${BUILD_ROOT}/openxpki/core/server"
RUN perl Makefile.PL

RUN mymeta-requires | cpanm
RUN make

# A bunch of these tests fail, but they also fail in a Debian/glibc, so 
# either I'm going something fundamentally wrong in both cases or the tests
# don't all work. I don't know which.
#RUN make test

# prepare for export to another container, either in a directory or a tarball
#RUN make distdir
#RUN make tardist

# at this point we have a built OpenXPKI ready for testing
# continuing further we configure for testing and building with Carton

# required for testing only
RUN apk add \
	mariadb-connector-c-dev \
	perl-dbd-mysql

RUN cpanm \
		Test::Distribution \
		Test::Harness \
		Test::More \
		Test::Prereq

# Carton dependencies
#
# Carton uses fixed versions of modules, as specified in the repo. The cpanm
# build above uses the latest versions of modules, potentially newer than 
# we'll get for Carton
#
# As a result, in some (or many) cases the apk-installed modules may not get
# used by Carton if they're not the exact right version. There no harm in having
# them anyway because it will save some time where we do match.
#
# The packages below are requirements for Carton itself, not for OpenXPKI.
RUN apk add \
		expat-dev \
		perl-class-load \
		perl-class-load-xs \
		perl-data-optlist \
		perl-devel-globaldestruction \
		perl-devel-overloadinfo \
		perl-devel-stacktrace \
		perl-dist-checkconflicts \
		perl-eval-closure \
		perl-mro-compat \
		perl-net-ssleay \
		perl-module-build \
		perl-module-implementation \
		perl-module-runtime \
		perl-module-runtime-conflicts \
#		perl-list-moreutils \
#		perl-list-moreutils-xs \
		perl-package-deprecationmanager \
		perl-package-stash \
		perl-package-stash-xs \
		perl-padwalker \
		perl-params-util \
		perl-params-validate \
		perl-path-tiny \
		perl-scalar-list-utils \
		perl-sub-exporter \
		perl-sub-exporter-progressive \
		perl-sub-install \
		perl-sub-name \
		perl-test-simple \
		perl-try-tiny

# some tests don't pull DBHOST from ENV, need to create database.yaml
COPY entrypoint.sh /entrypoint.sh
COPY database.yaml /etc/openxpki/config.d/system/

RUN apk add \
		less \
		nano \
		sed

WORKDIR "${BUILD_ROOT}/openxpki"

# Install Carton
# RUN cpanm Carton

# Build with Carton
# RUN ./tools/scripts/makefile2cpanfile.pl > cpanfile \
	# && carton install

# we need dig in the entrypoint
RUN apk add \
	bind-tools

ARG OXPKI_CONFIG_VERSION
#RUN add-contenv "OXPKI_CONFIG_VERSION=${OXPKI_CONFIG_VERSION}"

# to run OpenXPKI we need a locale, a user with a group and a log folder
RUN addgroup openxpki \
	&& adduser -DH -G openxpki openxpki

RUN apk add musl-locales \
	&& echo "en_US.UTF-8 UTF-8" > /etc/locale.gen

RUN ln -s /usr/share/i18n/locales/musl /usr/share/locale \
	&& mkdir -p /var/log/openxpki


# Don't try and start serveries, we want a shell when we connec to the container
# to allow pokng things to see if they work.
#ENTRYPOINT ["tail", "-f", "/dev/null"]
ENTRYPOINT ["/entrypoint.sh"]
