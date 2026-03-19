#!/bin/sh
# =============================================================================
# Self-signed TLS Certificate Generator
# Runs once as an init container (cert-gen service in docker-compose).
# Produces:
#   root_ca.key         — CA private key  (keep secret, used only to sign the cert)
#   root_ca.crt         — CA certificate  (distribute to clients / browsers)
#   custom-server.key   — Custom Server private key
#   custom-server.csr   — Custom Server certificate signing request
#   custom-server.crt   — Custom Server certificate signed by our CA
#   extfile.cnf — SAN extension config used during signing
# =============================================================================
set -eu

CERTS_DIR="${CERTS_DIR:-/certs}"
HOSTNAME="${HOSTNAME:-custom-server}"
COUNTRY="${TLS_COUNTRY:-US}"
STATE="${TLS_STATE:-New York}"
CITY="${TLS_CITY:-Albany}"
ORG="${TLS_ORG:-IT Company}"
OU="${TLS_OU:-IT}"
DAYS="${TLS_DAYS:-3650}"
EXTRA_SANS="${TLS_EXTRA_SANS:-}"

mkdir -p "${CERTS_DIR}"

ROOT_CA_KEY="${CERTS_DIR}/root_ca.key"
ROOT_CA_CERT="${CERTS_DIR}/root_ca.crt"
SERVER_KEY="${CERTS_DIR}/custom-server.key"
SERVER_CSR="${CERTS_DIR}/custom-server.csr"
SERVER_CERT="${CERTS_DIR}/custom-server.crt"
EXTFILE="${CERTS_DIR}/extfile.cnf"

# ---------------------------------------------------------------------------
# Skip if certs already exist (safe to restart the stack)
# ---------------------------------------------------------------------------
if [ -f "${SERVER_CERT}" ] && [ -f "${SERVER_KEY}" ]; then
  echo "[cert-gen] Certificates already exist. Skipping generation."
  exit 0
fi

echo "[cert-gen] Generating TLS certificates for hostname: ${HOSTNAME}"

# ---------------------------------------------------------------------------
# Validate existing CA material before generation.
# ---------------------------------------------------------------------------
if [ -f "${ROOT_CA_KEY}" ] && [ ! -f "${ROOT_CA_CERT}" ]; then
  echo "[cert-gen] Found ${ROOT_CA_KEY} but ${ROOT_CA_CERT} is missing."
  echo "[cert-gen] Remove the orphaned CA key or restore the CA certificate and try again."
  exit 1
fi

if [ -f "${ROOT_CA_CERT}" ] && [ ! -f "${ROOT_CA_KEY}" ]; then
  echo "[cert-gen] Found ${ROOT_CA_CERT} but ${ROOT_CA_KEY} is missing."
  echo "[cert-gen] Remove the orphaned CA certificate or restore the CA key and try again."
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Generate CA key and self-signed CA certificate
# ---------------------------------------------------------------------------
if [ -f "${ROOT_CA_KEY}" ] && [ -f "${ROOT_CA_CERT}" ]; then
  echo "[cert-gen] Reusing existing CA key and certificate."
else
  openssl genrsa -out "${ROOT_CA_KEY}" 4096
  openssl req -new -x509 \
    -key "${ROOT_CA_KEY}" \
    -out "${ROOT_CA_CERT}" \
    -days "${DAYS}" \
    -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORG}/OU=${OU} CA/CN=${ORG} Internal CA"

  echo "[cert-gen] CA certificate generated."
fi

# ---------------------------------------------------------------------------
# 2. Generate custom server private key and CSR
# ---------------------------------------------------------------------------
openssl genrsa -out "${SERVER_KEY}" 4096
openssl req -new \
  -key "${SERVER_KEY}" \
  -out "${SERVER_CSR}" \
  -subj "/C=${COUNTRY}/ST=${STATE}/L=${CITY}/O=${ORG}/OU=${OU}/CN=${HOSTNAME}"

echo "[cert-gen] Server CSR generated."

# ---------------------------------------------------------------------------
# 3. Build the SAN extension config
#    Include only user-controlled entries: the configured hostname and any
#    explicitly provided SAN values from TLS_EXTRA_SANS.
#    Bare values are treated as DNS names for convenience.
# ---------------------------------------------------------------------------
SAN_LIST="DNS:${HOSTNAME}"
if [ -n "${EXTRA_SANS}" ]; then
  OLD_IFS="${IFS}"
  IFS=','
  set -- ${EXTRA_SANS}
  IFS="${OLD_IFS}"

  for san_entry in "$@"; do
    case "${san_entry}" in
      DNS:*|IP:*|URI:*|email:*|RID:*|dirName:*|otherName:*)
        SAN_LIST="${SAN_LIST},${san_entry}"
        ;;
      *)
        SAN_LIST="${SAN_LIST},DNS:${san_entry}"
        ;;
    esac
  done
fi

cat > "${EXTFILE}" <<EOF
[ v3_req ]
subjectAltName          = ${SAN_LIST}
basicConstraints        = CA:FALSE
keyUsage                = critical, digitalSignature, keyEncipherment
extendedKeyUsage        = serverAuth
EOF

echo "[cert-gen] SAN config: ${SAN_LIST}"

# ---------------------------------------------------------------------------
# 4. Sign the custom server certificate with our CA
# ---------------------------------------------------------------------------
openssl x509 -req \
  -in "${SERVER_CSR}" \
  -CA "${ROOT_CA_CERT}" \
  -CAkey "${ROOT_CA_KEY}" \
  -CAcreateserial \
  -out "${SERVER_CERT}" \
  -days "${DAYS}" \
  -extensions v3_req \
  -extfile "${EXTFILE}"

echo "[cert-gen] Server certificate signed."

# ---------------------------------------------------------------------------
# 5. Set safe file permissions
#    custom-server.key must only be readable by the current user
# ---------------------------------------------------------------------------
chmod 600 "${ROOT_CA_KEY}" "${SERVER_KEY}"
chmod 644 "${ROOT_CA_CERT}" "${SERVER_CERT}"
# Keep the CA serial for future certificates signed by the same CA.
rm -f "${SERVER_CSR}"

echo "[cert-gen] Done. Files in ${CERTS_DIR}:"
ls -lah "${CERTS_DIR}"
