#!/bin/sh
# shellcheck shell=sh disable=SC2034,SC2154,SC2174

set -e

print_msg () { printf '[%s] %s' "${0##*/}" "${@}"; }
echo_msg () { print_msg "${*}"; echo; }

Debug='true'
# MyPerl='true'
[ "x${MyPerl}" = 'xtrue' ] && [ -d /opt/myperl/bin ] && export PATH=/opt/myperl/bin:$PATH

#
# basic openxpki settings
#
BASE='/etc/openxpki';
OPENXPKI_CONFIG="${BASE}/config.d/system/server.yaml"
if [ -f "${OPENXPKI_CONFIG}" ]
then
   eval "$(egrep '^user:|^group:' "${OPENXPKI_CONFIG}" | sed -e 's/:  */=/g')"
else
   echo_msg "ERROR: It seems that openXPKI is not installed at the default location (${BASE})!"
   echo_msg "Please install OpenXPKI or set BASE to the new PATH!"
   exit 1
fi

REALM="${OXPKI_SETUP_REALM:-democa}"
REALM_DIR="${BASE}/config.d/realm/${REALM}"
REALM_USERDB="${REALM_DIR}/userdb.yaml"
CA_IMPORT_DIR="${OXPKI_SETUP_IMPORT_DIR:-/import}"
FQDN="${OXPKI_SETUP_FQDN:-$(hostname -f)}"

# delete the democa softlink if it exists and we're not using it
[ "x${REALM}" != "xdemoca" ] \
  && rm -f "${BASE}/config.d/realm/democa" 2>/dev/null

# for automated testing we can set this via the environment, otherwise
# generate random key passwords
[ ! -z "${OXPKI_SETUP_KEY_PASS+set}" ] \
  && KEY_PASSWORD="${OXPKI_SETUP_KEY_PASS}" \
  || unset KEY_PASSWORD

# configure the realm
if [ ! -d "${REALM_DIR}" ]; then
  mkdir -p "${REALM_DIR}"

  cd "${REALM_DIR}"
  mkdir workflow workflow/def profile notification
  ln -s ../../realm.tpl/api/ .
  ln -s ../../realm.tpl/crl/ .

  # we're overwriting most of the fules in auth/, but copy them anyway so we
  # can easily fallback to default behaviour during development/testing
  cp -r ../../realm.tpl/auth .

  ln -s ../../realm.tpl/uicontrol/ .
  cp ../../realm.tpl/profile/default.yaml profile/
  ln -s ../../../realm.tpl/profile/template/ profile/
  cp ../../realm.tpl/notification/smtp.yaml.sample notification/smtp.yaml
  ln -s ../../../realm.tpl/workflow/global workflow/
  ln -s ../../../realm.tpl/workflow/persister.yaml workflow/

  salt="$(openssl rand -base64 3)"
  RAOP_PASS="${OXPKI_SETUP_RAOP_PASS:-openxpki}"
  RAOP_NAME="${OXPKI_SETUP_RAOP_NAME:-raop}"
  RAOP_HASH="{ssha}$(printf '%s' "$(printf '%s' "${RAOP_PASS}${salt}" | openssl sha1 -binary)${salt}" | openssl enc -base64)"

  ## auth/stack.yaml
  echo "
Anonymous:
  label: Anonymous
  handler: Anonymous
  type: anon

User:
  label: User Login
  handler: User NoAuth
  type: passwd

Operator:
  label: Operator Login
  handler: Operator Password
  type: passwd

# Certificate:
#   label: Client certificate
#   handler: Certificate
#   type: x509
#   sign:
#     # This is the public key matching the private one given in webui/default.conf
#     # Use \"openssl pkey -pubout\" to create the required string from the private key
#     # key: MFkwEwYHK.......pK7qV/FmDw==

_System:
    handler: System
" > auth/stack.yaml


  ## auth/handler.yaml
  echo "
# Certificate:
#   type: ClientX509
#   role: User
#   arg: CN
#   trust_anchor:
#     realm: ${REALM}

Anonymous:
  type: Anonymous
  label: Anonymous

User NoAuth:
  type: NoAuth
  role: User

User Password:
  type: Password
  user@: connector:auth.connector.userdb

Operator Password:
  type: Password
  # The passwords can be generated with \"openxpkiadm hashpwd\"
  # or with \"openssl passwd -5\"
  # The password below is \"openxpki\" for all three users
  role: RA Operator
  user:
    ${RAOP_NAME}: \"${RAOP_HASH}\"

System:
  type: Anonymous
  role: System

# Sample using a Password \"bind\" connector
Password Connector:
  type: Connector
  role: User
  source@: connector:auth.connector.localuser
" > auth/handler.yaml

  ## ${REALM}/userdb.yaml
  echo "
${RAOP_NAME}:
    digest: \"${RAOP_HASH}\"
    role: RA Operator
" > "${REALM_USERDB}"

  ## crypto.yaml
  echo "
# Default realm token configuration
type:
  certsign: ca-signer
  datasafe: vault
  scep: scep

# The actual token setup, based on current token.xml
token:
  default:
    backend: OpenXPKI::Crypto::Backend::OpenSSL

    # Template to create key, available vars are
    # ALIAS (ca-signer-1), GROUP (ca-signer), GENERATION (1)
    key: ${BASE}/local/keys/[% PKI_REALM %]/[% ALIAS %].pem

    # possible values are OpenSSL, nCipher, LunaCA
    engine: OpenSSL
    engine_section: ''
    engine_usage: ''
    key_store: OPENXPKI

    # OpenSSL binary location
    shell: /usr/bin/openssl

    # OpenSSL binary call gets wrapped with this command
    wrapper: ''

    # random file to use for OpenSSL
    randfile: /var/openxpki/rand

    # Default value for import, recorded in database, can be overriden
    secret: default

  ca-signer:
    inherit: default
    key_store: DATAPOOL
    key: \"[% ALIAS %]\"
    secret: ca-signer

  vault:
    inherit: default
    key: ${BASE}/local/keys/[% ALIAS %].pem
    secret: vault

  scep:
    inherit: default
    backend: OpenXPKI::Crypto::Tool::LibSCEP
    key_store: DATAPOOL
    key: \"[% ALIAS %]\"
    secret: scep

# Define the secret groups
secret:
  default:
    # this let OpenXPKI use the secret of the same name from system.crypto
    # if you do not want to share the secret just replace this line with
    # the config found in system.crypto. You can create additional secrets
    # by adding similar blocks with another key
    import: 1

  ca-signer:
    label: CA signer group
    method: literal
    value: ISSUING_CA_PASS

  vault:
    label: Vault group
    method: literal
    value: DATAVAULT_PASS

  scep:
    label: SCEP group
    method: literal
    value: SCEP_RA_PASS
" > crypto.yaml

  sed -E \
    -e "s|(^\s+LOCATION:\s+).*|\1${REALM_USERDB}|" \
    -i auth/connector.yaml

  (cd workflow/def/ && find ../../../../realm.tpl/workflow/def/ -type f -print0 | xargs -0 -L1 ln -s)

  # In most cases you do not need all workflows and we recommend to remove them
  # those items are rarely used
#  cd workflow/def
#  rm certificate_export.yaml certificate_revoke_by_entity.yaml report_list.yaml
  # if you dont plan to use EST remove those too
#  rm est_cacerts.yaml est_csrattrs.yaml

  SYSTEM_REALMS="${BASE}/config.d/system/realms.yaml"

  # if there's nothing but `democa` in the realms.yaml, overwrite it completely
  if ! cat "${SYSTEM_REALMS}" | grep -xo '^\w*:$' | grep -vq 'democa:'; then
    rm -f "${SYSTEM_REALMS}"
  fi

  # add this realm to system/realms.yaml if it's not already present
  if ! grep -Fxq "${REALM}:" "${SYSTEM_REALMS}" 2>/dev/null; then
    printf '\n%s:\n    label: %s CA\n' "${REALM}" "${REALM}" >> "${SYSTEM_REALMS}"
  fi

  # don't leave these hanging around
  unset RAOP_NAME
  unset RAOP_PASS
  unset RAOP_HASH
fi

print_msg 'Using CA directory: '
if [ -z "${OXPKI_SETUP_CA_DIR+set}" ]; then
   TMP_CA_DIR=$(mktemp -d)
elif mkdir -p "${OXPKI_SETUP_CA_DIR}"; then
   TMP_CA_DIR="${OXPKI_SETUP_CA_DIR}"
else
   echo_msg "ERROR: Could not create CA directory ${OXPKI_SETUP_CA_DIR}"
   exit 1;
fi && echo "${TMP_CA_DIR}"


make_password() {
    PASSWORD_FILE=$1;
    touch "${PASSWORD_FILE}"
    chown ${user}:root "${PASSWORD_FILE}"
    chmod 640 "${PASSWORD_FILE}"
    if [ -z "$KEY_PASSWORD" ]; then
        dd if=/dev/urandom bs=32 count=1 2>/dev/null | base64 >"${PASSWORD_FILE}"
    else
        printf '%s' "$KEY_PASSWORD" > "${PASSWORD_FILE}"
    fi;
}

#
# CA and certificate settings
#

BACKUP_SUFFIX='~'
GENERATION=$(date +%Y%m%d)

# root CA selfsigned (in production use company's root certificate)
ROOT_CA='OpenXPKI_Root_CA'
ROOT_CA_REQUEST="${TMP_CA_DIR}/${ROOT_CA}.csr"
ROOT_CA_KEY="${TMP_CA_DIR}/${ROOT_CA}.key"
ROOT_CA_KEY_PASSWORD="${TMP_CA_DIR}/${ROOT_CA}.pass"
ROOT_CA_CERTIFICATE="${TMP_CA_DIR}/${ROOT_CA}.crt"
ROOT_CA_SUBJECT="${OXPKI_SETUP_ROOT_CA_SUBJECT:-/CN=${REALM} Root CA} ${GENERATION}"
ROOT_CA_SERVER_FQDN="${FQDN:-rootca.openxpki.net}"

# issuing CA signed by root CA above
ISSUING_CA='OpenXPKI_Issuing_CA'
ISSUING_CA_REQUEST="${TMP_CA_DIR}/${ISSUING_CA}.csr"
ISSUING_CA_KEY="${TMP_CA_DIR}/${ISSUING_CA}.key"
ISSUING_CA_KEY_PASSWORD="${TMP_CA_DIR}/${ISSUING_CA}.pass"
ISSUING_CA_CERTIFICATE="${TMP_CA_DIR}/${ISSUING_CA}.crt"
ISSUING_CA_SUBJECT="${OXPKI_SETUP_ISSUING_CA_SUBJECT:-/O=${REALM}/OU=PKI/CN=${REALM} Issuing CA} ${GENERATION}"

# SCEP registration authority certificate signed by root CA above
SCEP='OpenXPKI_SCEP_RA'
SCEP_REQUEST="${TMP_CA_DIR}/${SCEP}.csr"
SCEP_KEY="${TMP_CA_DIR}/${SCEP}.key"
SCEP_KEY_PASSWORD="${TMP_CA_DIR}/${SCEP}.pass"
SCEP_CERTIFICATE="${TMP_CA_DIR}/${SCEP}.crt"
SCEP_SUBJECT="/CN=${FQDN}:scep-ra"

# Apache WEB certificate signed by root CA above
WEB='OpenXPKI_WebUI'
WEB_REQUEST="${TMP_CA_DIR}/${WEB}.csr"
WEB_KEY="${TMP_CA_DIR}/${WEB}.key"
WEB_KEY_PASSWORD="${TMP_CA_DIR}/${WEB}.pass"
WEB_CERTIFICATE="${TMP_CA_DIR}/${WEB}.crt"
WEB_SUBJECT="/CN=${FQDN}"
WEB_SERVER_FQDN="${FQDN}"

# data vault certificate selfsigned
DATAVAULT='OpenXPKI_DataVault'
DATAVAULT_REQUEST="${TMP_CA_DIR}/${DATAVAULT}.csr"
DATAVAULT_KEY="${TMP_CA_DIR}/${DATAVAULT}.key"
DATAVAULT_KEY_PASSWORD="${TMP_CA_DIR}/${DATAVAULT}.pass"
DATAVAULT_CERTIFICATE="${TMP_CA_DIR}/${DATAVAULT}.crt"
DATAVAULT_SUBJECT='/CN=DataVault'

#
# openssl.conf
#
BITS=3072
DAYS=730 # 2 years (default value not used for further enhancements)
RDAYS="3655" # 10 years for root
IDAYS="1828" # 5 years for issuing
SDAYS="365" # 1 years for scep
WDAYS="1096" # 3 years web
DDAYS="$RDAYS" # 10 years datavault (same a root)

# creation neccessary directories and files
[ -d "${TMP_CA_DIR}" ] || mkdir -m 755 -p "${TMP_CA_DIR}" && chown ${user}:root "${TMP_CA_DIR}"
OPENSSL_DIR="${TMP_CA_DIR}/.openssl"
[ -d "${OPENSSL_DIR}" ] || mkdir -m 700 "${OPENSSL_DIR}" && chown root:root "${OPENSSL_DIR}"
cd "${OPENSSL_DIR}";

OPENSSL_CONF="${OPENSSL_DIR}/openssl.cnf"
print_msg "creating configuration for openssl ($OPENSSL_CONF) .. "

touch "${OPENSSL_DIR}/index.txt"
touch "${OPENSSL_DIR}/index.txt.attr"
echo 00 > "${OPENSSL_DIR}/crlnumber"

echo "
HOME			= .
#RANDFILE		= \$ENV::HOME/.rnd

[ ca ]
default_ca		= CA_default

[ CA_default ]
dir			= ${OPENSSL_DIR}
certs			= ${OPENSSL_DIR}/certs
crl_dir			= ${OPENSSL_DIR}/
database		= ${OPENSSL_DIR}/index.txt
new_certs_dir		= ${OPENSSL_DIR}/
serial			= ${OPENSSL_DIR}/serial
crlnumber		= ${OPENSSL_DIR}/crlnumber

crl			= ${OPENSSL_DIR}/crl.pem
private_key		= ${OPENSSL_DIR}/cakey.pem
#RANDFILE		= ${OPENSSL_DIR}/.rand

default_md		= sha256
preserve		= no
policy			= policy_none
default_days		= ${DAYS}

# x509_extensions               = v3_ca_extensions
# x509_extensions               = v3_issuing_extensions
# x509_extensions               = v3_datavault_extensions
# x509_extensions               = v3_scep_extensions
# x509_extensions               = v3_web_extensions

[policy_none]
countryName             = optional
organizationName        = optional
domainComponent		= optional
organizationalUnitName	= optional
commonName		= supplied

[ req ]
default_bits		= ${BITS}
distinguished_name	= req_distinguished_name

# x509_extensions               = v3_ca_reqexts # not for root self signed, only for issuing
## x509_extensions              = v3_datavault_reqexts # not required self signed
# x509_extensions               = v3_scep_reqexts
# x509_extensions               = v3_web_reqexts

[ req_distinguished_name ]
domainComponent		= Domain Component
commonName		= Common Name

[ v3_ca_reqexts ]
subjectKeyIdentifier    = hash
keyUsage                = digitalSignature, keyCertSign, cRLSign

[ v3_datavault_reqexts ]
subjectKeyIdentifier    = hash
keyUsage                = keyEncipherment
extendedKeyUsage        = emailProtection

[ v3_scep_reqexts ]
subjectKeyIdentifier    = hash

[ v3_web_reqexts ]
subjectKeyIdentifier    = hash
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = serverAuth, clientAuth


[ v3_ca_extensions ]
subjectKeyIdentifier    = hash
keyUsage                = digitalSignature, keyCertSign, cRLSign
basicConstraints        = critical,CA:TRUE
authorityKeyIdentifier  = keyid:always,issuer

[ v3_issuing_extensions ]
subjectKeyIdentifier    = hash
keyUsage                = digitalSignature, keyCertSign, cRLSign
basicConstraints        = critical,CA:TRUE
authorityKeyIdentifier  = keyid:always,issuer:always
#crlDistributionPoints	= ${ROOT_CA_REVOCATION_URI}
#authorityInfoAccess	= caIssuers;${ROOT_CA_CERTIFICATE_URI}

[ v3_datavault_extensions ]
subjectKeyIdentifier    = hash
keyUsage                = keyEncipherment
extendedKeyUsage        = emailProtection
basicConstraints        = CA:FALSE
authorityKeyIdentifier  = keyid:always,issuer

[ v3_scep_extensions ]
subjectKeyIdentifier    = hash
keyUsage                = digitalSignature, keyEncipherment
basicConstraints        = CA:FALSE
authorityKeyIdentifier  = keyid,issuer

[ v3_web_extensions ]
subjectKeyIdentifier    = hash
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = serverAuth, clientAuth
basicConstraints        = critical,CA:FALSE
subjectAltName		= DNS:${WEB_SERVER_FQDN}
#crlDistributionPoints	= ${ISSUING_REVOCATION_URI}
#authorityInfoAccess	= caIssuers;${ISSUING_CERTIFICATE_URI}
" > "${OPENSSL_CONF}"

echo 'done.'

[ "x${Debug}" = 'xtrue' ] || exec 2>/dev/null

echo_msg 'Checking certificates..'

# be aware of certificate heirachy when importing from files
# i.e. there's no point importing a SCEP certificate if we've generated the
# root CA, they won't match
allowCertImports='True'

check_file_import () {
  if [ -f "${1}" ]; then
    [ "x${allowCertImports}" != "xTrue" ] \
      && echo 'found, SKIPPED' && return 1
    echo "found in $(dirname "${1}")"
    return 0
  else
    echo 'missing'
    return 1
  fi
}

# self signed root
print_msg 'Root CA.. '
if [ ! -e "${ROOT_CA_CERTIFICATE}" ]; then
  if check_file_import "${CA_IMPORT_DIR}/${ROOT_CA}.crt"; then
    cp ${CA_IMPORT_DIR}/${ROOT_CA}* ${TMP_CA_DIR}
  else
    allowCertImports='False'

    echo_msg 'Creating self-signed root CA.. '
    [ -f "${ROOT_CA_KEY}" ] \
      && mv "${ROOT_CA_KEY}" "${ROOT_CA_KEY}${BACKUP_SUFFIX}"
    [ -f "${ROOT_CA_KEY_PASSWORD}" ] \
      && mv "${ROOT_CA_KEY_PASSWORD}" "${ROOT_CA_KEY_PASSWORD}${BACKUP_SUFFIX}"
    make_password "${ROOT_CA_KEY_PASSWORD}"
    openssl req -config "${OPENSSL_CONF}" -extensions v3_ca_extensions -batch -x509 -newkey rsa:$BITS -days ${RDAYS} -passout file:"${ROOT_CA_KEY_PASSWORD}" -keyout "${ROOT_CA_KEY}" -subj "${ROOT_CA_SUBJECT}" -out "${ROOT_CA_CERTIFICATE}"
  fi
else echo 'OK'
fi

# abort if something went wrong
[ ! -e "${ROOT_CA_KEY}" ] \
  && echo_msg "ERROR: No '${ROOT_CA_KEY}' key file!" \
  && exit 1

# signing certificate (issuing)
print_msg 'Issuing CA.. '
if [ ! -e "${ISSUING_CA_KEY}" ]; then
  if check_file_import "${CA_IMPORT_DIR}/${ISSUING_CA}.key"; then
    cp ${CA_IMPORT_DIR}/${ISSUING_CA}* ${TMP_CA_DIR}
  else
    allowCertImports='False'

    echo_msg 'Creating issuing CA request.. '
    [ -f "${ISSUING_CA_REQUEST}" ] \
      && mv "${ISSUING_CA_REQUEST}" "${ISSUING_CA_REQUEST}${BACKUP_SUFFIX}"
    make_password "${ISSUING_CA_KEY_PASSWORD}"
    openssl req -config "${OPENSSL_CONF}" -reqexts v3_ca_reqexts -batch -newkey rsa:$BITS -passout file:"${ISSUING_CA_KEY_PASSWORD}" -keyout "${ISSUING_CA_KEY}" -subj "${ISSUING_CA_SUBJECT}" -out "${ISSUING_CA_REQUEST}"

    echo_msg 'Signing issuing certificate with own root CA.. '
    [ -f "${ISSUING_CA_CERTIFICATE}" ] \
      && mv "${ISSUING_CA_CERTIFICATE}" "${ISSUING_CA_CERTIFICATE}${BACKUP_SUFFIX}"
    openssl ca -create_serial -config "${OPENSSL_CONF}" -extensions v3_issuing_extensions -batch -days ${IDAYS} -in "${ISSUING_CA_REQUEST}" -cert "${ROOT_CA_CERTIFICATE}" -passin file:"${ROOT_CA_KEY_PASSWORD}" -keyfile "${ROOT_CA_KEY}" -out "${ISSUING_CA_CERTIFICATE}"
  fi
  sed -e "s|ISSUING_CA_PASS|$(cat "${ISSUING_CA_KEY_PASSWORD}")|" -i "${REALM_DIR}/crypto.yaml"

elif [ ! -e "${ISSUING_CA_CERTIFICATE}" ]; then
  if check_file_import "${CA_IMPORT_DIR}/${ISSUING_CA}.crt"; then
    cp ${CA_IMPORT_DIR}/${ISSUING_CA}* ${TMP_CA_DIR}
  else
    allowCertImports='False'

    echo_msg 'Signing issuing certificate with own root CA.. '
    openssl ca -create_serial -config "${OPENSSL_CONF}" -extensions v3_issuing_extensions -batch -days ${IDAYS} -in "${ISSUING_CA_REQUEST}" -cert "${ROOT_CA_CERTIFICATE}" -passin file:"${ROOT_CA_KEY_PASSWORD}" -keyfile "${ROOT_CA_KEY}" -out "${ISSUING_CA_CERTIFICATE}"
  fi
else echo 'OK'
fi

# Data Vault is only used internally, use self signed
# this one doesn't rely on the root CA so no need to check $allowCertImports
print_msg 'DavaVault.. '
if [ ! -e "${DATAVAULT_KEY}" ]; then
  if [ -f "${CA_IMPORT_DIR}/${DATAVAULT}.key" ]; then
    cp ${CA_IMPORT_DIR}/${DATAVAULT}* ${TMP_CA_DIR}
  else
    echo_msg 'Creating a self signed DataVault certificate.. '
    [ -f "${DATAVAULT_CERTIFICATE}" ] \
      && mv "${DATAVAULT_CERTIFICATE}" "${DATAVAULT_CERTIFICATE}${BACKUP_SUFFIX}"
    make_password "${DATAVAULT_KEY_PASSWORD}"
    (openssl req -config "${OPENSSL_CONF}" -extensions v3_datavault_extensions -batch -x509 -newkey rsa:$BITS -days ${DDAYS} -passout file:"${DATAVAULT_KEY_PASSWORD}" -keyout "${DATAVAULT_KEY}" -subj "${DATAVAULT_SUBJECT}" -out "${DATAVAULT_CERTIFICATE}") &
    wait $!
  fi
  sed -e "s|DATAVAULT_PASS|$(cat "${DATAVAULT_KEY_PASSWORD}")|" -i "${REALM_DIR}/crypto.yaml"
else echo 'OK'
fi

# SCEP certificate
print_msg 'SCEP.. '
if [ ! -e "${SCEP_KEY}" ]; then
  if check_file_import "${CA_IMPORT_DIR}/${SCEP}.key"; then
    cp ${CA_IMPORT_DIR}/${SCEP}* ${TMP_CA_DIR}
  else
    echo_msg 'Creating a SCEP request.. '
    [ -f "${SCEP_REQUEST}" ] \
      && mv "${SCEP_REQUEST}" "${SCEP_REQUEST}${BACKUP_SUFFIX}"
    make_password "${SCEP_KEY_PASSWORD}"
    openssl req -config "${OPENSSL_CONF}" -reqexts v3_scep_reqexts -batch -newkey rsa:$BITS -passout file:"${SCEP_KEY_PASSWORD}" -keyout "${SCEP_KEY}" -subj "${SCEP_SUBJECT}" -out "${SCEP_REQUEST}"

    echo_msg 'Signing SCEP certificate with Issuing CA.. '
    [ -f "${SCEP_CERTIFICATE}" ] \
      && mv "${SCEP_CERTIFICATE}" "${SCEP_CERTIFICATE}${BACKUP_SUFFIX}"
    openssl ca -create_serial -config "${OPENSSL_CONF}" -extensions v3_scep_extensions -batch -days ${SDAYS} -in "${SCEP_REQUEST}" -cert "${ISSUING_CA_CERTIFICATE}" -passin file:"${ISSUING_CA_KEY_PASSWORD}" -keyfile "${ISSUING_CA_KEY}" -out "${SCEP_CERTIFICATE}"
  fi
  sed -e "s|SCEP_RA_PASS|$(cat "${SCEP_KEY_PASSWORD}")|" -i "${REALM_DIR}/crypto.yaml"
else echo 'OK'
fi


# web certificate
print_msg 'Web.. '
if [ ! -e "${WEB_KEY}" ]; then
  if check_file_import "${CA_IMPORT_DIR}/${WEB}.key"; then
    cp ${CA_IMPORT_DIR}/${WEB}* ${TMP_CA_DIR}
  else
    echo_msg 'Creating a Web request.. '
    [ -f "${WEB_REQUEST}" ] \
      && mv "${WEB_REQUEST}" "${WEB_REQUEST}${BACKUP_SUFFIX}"
    make_password "${WEB_KEY_PASSWORD}"
    openssl req -config "${OPENSSL_CONF}" -reqexts v3_web_reqexts -batch -newkey rsa:$BITS -passout file:"${WEB_KEY_PASSWORD}" -keyout "${WEB_KEY}" -subj "${WEB_SUBJECT}" -out "${WEB_REQUEST}"

    echo_msg 'Signing Web certificate with Issuing CA.. '
    [ -f "${WEB_CERTIFICATE}" ] \
      && mv "${WEB_CERTIFICATE}" "${WEB_CERTIFICATE}${BACKUP_SUFFIX}"
    openssl ca -create_serial -config "${OPENSSL_CONF}" -extensions v3_web_extensions -batch -days ${WDAYS} -in "${WEB_REQUEST}" -cert "${ISSUING_CA_CERTIFICATE}" -passin file:"${ISSUING_CA_KEY_PASSWORD}" -keyfile "${ISSUING_CA_KEY}" -out "${WEB_CERTIFICATE}"
  fi
else echo 'OK'
fi

cd $OLDPWD;
# rm $TMP/*;
# rmdir $TMP;

# chown/chmod
chmod 400 ${TMP_CA_DIR}/*.pass
chmod 440 ${TMP_CA_DIR}/*.key
chmod 444 ${TMP_CA_DIR}/*.crt
chown root:root ${TMP_CA_DIR}/*.csr ${TMP_CA_DIR}/*.key ${TMP_CA_DIR}/*.pass
chown root:${group} ${TMP_CA_DIR}/*.crt ${TMP_CA_DIR}/*.key

print_msg 'Starting server before imports.. '
openxpkictl start >/dev/null && echo 'OK'

echo_msg 'Importing certificates..'
mkdir -p "${BASE}/local/keys"

# the import command with the --key parameter takes care to copy the key
# files to the datapool or filesystem locations
echo_msg 'Importing root..'
openxpkiadm certificate import --force-certificate-ignore-existing --file "${ROOT_CA_CERTIFICATE}"

echo_msg 'Importing DataVault..'
openxpkiadm alias --force-ignore-existing --file "${DATAVAULT_CERTIFICATE}" --realm "${REALM}" --token datasafe --key ${DATAVAULT_KEY}

sleep 1

echo_msg 'Importing issuing CA..'
openxpkiadm alias --force-ignore-existing --file "${ISSUING_CA_CERTIFICATE}" --realm "${REALM}" --token certsign --key ${ISSUING_CA_KEY}

echo_msg 'Importing SCEP..'
openxpkiadm alias --force-ignore-existing --file "${SCEP_CERTIFICATE}" --realm "${REALM}" --token scep  --key ${SCEP_KEY}

echo_msg 'Importing certificates.. done'

print_msg 'Issuing CRL.. '
openxpkicmd  --realm "${REALM}" crl_issuance

# stop the server, otherwise we conflict with the init system
print_msg 'Stopping server after imports.. '
openxpkictl stop >/dev/null 2>&1 || true
echo 'OK'

# Setup the Webserver
print_msg 'Configuring apache.. '
a2enmod ssl rewrite headers >/dev/null && \
a2ensite openxpki >/dev/null && \
a2dissite 000-default default-ssl >/dev/null && \
echo 'OK'

if [ ! -e "${BASE}/tls/chain" ]; then
  print_msg 'Rehashing chains.. '
  mkdir -m755 -p "${BASE}/tls/chain"
  cp ${ROOT_CA_CERTIFICATE} "${BASE}/tls/chain/"
  cp ${ISSUING_CA_CERTIFICATE} "${BASE}/tls/chain/"
  c_rehash "${BASE}/tls/chain/" >/dev/null 2>&1 && echo 'OK'
fi

if [ ! -e "${BASE}/tls/endentity/openxpki.crt" ]; then
  print_msg 'End entity.. '
  mkdir -m755 -p "${BASE}/tls/endentity"
  mkdir -m700 -p "${BASE}/tls/private"
  cp ${WEB_CERTIFICATE} "${BASE}/tls/endentity/openxpki.crt"
  cat ${ISSUING_CA_CERTIFICATE} >> "${BASE}/tls/endentity/openxpki.crt"
  printf '%s.. ' "$(openssl rsa -in ${WEB_KEY} -passin file:${WEB_KEY_PASSWORD} -out "${BASE}/tls/private/openxpki.pem" 2>&1)"
  chmod 400 "${BASE}/tls/private/openxpki.pem"
  service apache2 restart >/dev/null
  echo 'done'
fi

print_msg 'Rehashing SSL certs.. '
cp ${ISSUING_CA_CERTIFICATE} /etc/ssl/certs
cp ${ROOT_CA_CERTIFICATE} /etc/ssl/certs
c_rehash /etc/ssl/certs >/dev/null 2>&1 && echo 'OK'

print_msg 'Stopping apache.. '
service apache2 stop >/dev/null 2>&1 || true
echo 'OK'

echo_msg "OpenXPKI default configuration complete."
