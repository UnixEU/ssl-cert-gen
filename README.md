# SSL Certificate Generator

This project generates a local Root Certificate Authority (RootCA) and a server TLS certificate by using Docker and OpenSSL.

It is meant for local development, testing, internal tools, and other non-production scenarios where you want to create trusted certificates for custom hostnames without depending on a public CA.

## What It Does

The application:

- creates a RootCA private key and certificate
- generates a private key and CSR for the server certificate
- signs the server certificate with the RootCA
- includes Subject Alternative Names (SANs) from the `.env` file
- stores all generated files in the local `certs/` directory

If `root_ca.key` and `root_ca.crt` already exist in `certs/`, they are reused on future runs. This lets you generate additional server certificates without importing a new CA into your local trust store each time.

## Project Files

- [docker-compose.yaml](./docker-compose.yaml) runs the OpenSSL container
- [scripts/generate-certs.sh](./scripts/generate-certs.sh) contains the certificate generation logic
- [.env](./.env) provides hostname, SANs, and certificate subject settings
- `certs/` is created on first run and contains the generated output

## Requirements

- Docker
- Docker Compose support via `docker compose`

## Configuration

The application reads values from `.env`.

Example:

```env
HOSTNAME=custom-server
TLS_COUNTRY=US
TLS_STATE=New York
TLS_CITY=Albany
TLS_ORG=IT Company
TLS_OU=IT
TLS_DAYS=3650
TLS_EXTRA_SANS=DNS:custom-server.internal,DNS:custom-server.local,IP:10.0.0.5
```

### Variables

- `HOSTNAME`: Common Name for the server certificate. It is also added to SAN automatically as `DNS:${HOSTNAME}`.
- `TLS_COUNTRY`: Certificate subject country.
- `TLS_STATE`: Certificate subject state or province.
- `TLS_CITY`: Certificate subject locality or city.
- `TLS_ORG`: Certificate subject organization.
- `TLS_OU`: Certificate subject organizational unit.
- `TLS_DAYS`: Certificate validity in days.
- `TLS_EXTRA_SANS`: Additional SAN entries, comma-separated, with no spaces. Bare hostnames are treated as DNS names automatically. Example: `DNS:api.local,api.internal,IP:127.0.0.1`

The script always includes this SAN by default:

- `DNS:${HOSTNAME}`

Any other SAN values must be provided through `TLS_EXTRA_SANS`. If you enter a bare hostname such as `api.internal`, the script converts it to `DNS:api.internal` automatically.

## How To Use

1. Update the values in `.env` for the hostname and any extra SAN entries you need.
2. Run the generator:

```bash
docker compose up ssl-cert-gen
```

3. Find the generated files in the local `certs/` directory.
4. Import `certs/root_ca.crt` into your local trust store if you want browsers or tools to trust certificates signed by this CA.

If you only need the container to run once and stop cleanly, you can also use:

```bash
docker compose run --rm ssl-cert-gen
```

## Generated Files

The following files are written to `certs/`:

- `root_ca.key`: RootCA private key
- `root_ca.crt`: RootCA certificate
- `root_ca.srl`: RootCA serial file used for future certificate signing
- `custom-server.key`: server private key
- `custom-server.crt`: signed server certificate
- `extfile.cnf`: SAN extension file used during signing

The temporary CSR is removed automatically after signing.

## Reuse Behavior

The script behaves as follows:

- if `custom-server.crt` and `custom-server.key` already exist, generation is skipped
- if `root_ca.key` and `root_ca.crt` already exist, the existing RootCA is reused
- if only one RootCA file exists, the script exits with an error to avoid inconsistent state

This means you can keep the same RootCA and create a new server certificate by deleting only the server certificate files:

```bash
rm -f certs/custom-server.crt certs/custom-server.key certs/custom-server.csr certs/extfile.cnf
docker compose up ssl-cert-gen
```

If you want to rotate the RootCA completely, remove the CA files as well:

```bash
rm -f certs/root_ca.crt certs/root_ca.key certs/root_ca.srl
rm -f certs/custom-server.crt certs/custom-server.key certs/custom-server.csr certs/extfile.cnf
docker compose up ssl-cert-gen
```

## Notes

- This project is intended for local or internal development use.
- Do not use this setup as-is for public production certificates.
- Keep `root_ca.key` private. Anyone with this key can sign certificates that chain to your RootCA.
