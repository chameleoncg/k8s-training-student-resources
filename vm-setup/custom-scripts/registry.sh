#!/usr/bin/env bash

# enable unofficial bash strict mode
set -o errexit
set -o nounset
set -o pipefail
shopt -s extglob

IFS=$'\n\t'

# =======directory paths=======
LOCAL_DIR="$(realpath $0 | sed 's|\(.*\)/.*|\1|')"
ROOT_DIR="${HOME}"

# =======logging functions=======
_INFO="\e[1;36m"  # Bold Cyan
_WARN="\e[1;33m"  # Bold Yellow
_SUCCESS="\e[1;32m"  # Bold Green
_ERROR="\e[1;31m"  # Bold Red
_CLR="\e[0m"  # Clear ANSI Codes

info() {
  printf "${_INFO}%s${_CLR}\n" "$1"
}

warn() {
  printf "${_WARN}%s${_CLR}\n" "$1"
}

success() {
  printf "${_SUCCESS}%s${_CLR}\n" "$1"
}

error() {
  printf "${_ERROR}%s${_CLR}\n" "$1"
}

fatal() {
  error "$@"; exit 1
}

# =======util functions=======
trap_add() {
  local trap_cmd="$1"
  shift || fatal "${FUNCNAME} usage error"
  for sig in "$@"; do
    trap -- "$(
      # Trap helper fn
      extract_trap_cmd() { printf '%s\n' "${3:-}"; }
      # print existing trap
      eval "extract_trap_cmd $(trap -p "${sig}")"
      # Print new trap
      printf '%s\n' "${trap_cmd}"
    )" "${sig}" || fatal "unable to add to trap ${sig}"
  done
}

# =======registry functions=======
REGISTRY_NAME="${REGISTRY_NAME:="lab.registry"}"
REGISTRY_IMAGE="${REGISTRY_IMAGE:="registry:2"}"
REGISTRY_PORT="${REGISTRY_PORT:="5050"}"
REGISTRY_INTERNAL_PORT="${REGISTRY_INTERNAL_PORT:="5000"}"
CHART_REPO="${CHART_REPO:="/charts"}"
IMAGE_REPO="${IMAGE_REPO:="/images"}"
OCI_REPO="${OCI_REPO:="/oci"}"
REGISTRY_STORE="${REGISTRY_STORE:="${ROOT_DIR}/.registry"}"
REGISTRY_TLS="${REGISTRY_TLS:=""}"
REGISTRY_CREDENTIALS="${INSECURE_REGISTRY:=""}"
REGISTRY_USER="${REGISTRY_USER:="admin"}"
REGISTRY_PSWD="${REGISTRY_PSWD:="$(tr -dc "A-Za-z0-9" </dev/random | head -c 24; echo)"}"

# Generate registry auth secret and certificate.
gen_auth() {
  if [ "${REGISTRY_TLS,,}" == "true" ] && [ ! -f "${REGISTRY_STORE}/certs/domain.crt" ]; then
    mkdir -p "${REGISTRY_STORE}/certs"
    openssl req -newkey rsa:4096 -nodes -sha256 \
                    -keyout "${REGISTRY_STORE}/certs/domain.key" -x509 -days 365 \
                    -subj "/CN=${REGISTRY_NAME}/O=${REGISTRY_NAME}/C=US" \
                    --addext "subjectAltName=DNS.1:${REGISTRY_NAME}" \
                    -out "${REGISTRY_STORE}/certs/domain.crt"
    # TODO Generate a containerd config to configure certs
  else
    mkdir -p "${REGISTRY_STORE}/containerd/certs.d/${REGISTRY_NAME}:${REGISTRY_INTERNAL_PORT}"
    cat <<EOL > "${REGISTRY_STORE}/containerd/certs.d/${REGISTRY_NAME}:${REGISTRY_INTERNAL_PORT}/hosts.toml"
server = "http://${REGISTRY_NAME}:${REGISTRY_INTERNAL_PORT}"

[host."http://${REGISTRY_NAME}:${REGISTRY_INTERNAL_PORT}"]
  skip_verify = true
EOL
  fi
  if [ "${REGISTRY_CREDENTIALS,,}" == "true" ] && [ ! -f "${REGISTRY_STORE}/auth/htpasswd" ]; then
    mkdir -p "${REGISTRY_STORE}/auth"
    docker run --rm --entrypoint htpasswd registry1.dso.mil/ironbank/opensource/apache/apache2:2.4.57 -Bbn "${REGISTRY_USER}" "${REGISTRY_PSWD}" > ${REGISTRY_STORE}/auth/htpasswd
    # TODO Generate a containerd config to configure auth
  fi
}

registry_up() {
  # Check to see if the registry is currently deployed.
  if [ "$(docker inspect -f '{{.State.Running}}' "local-registry" 2>/dev/null || true)" != 'true' ]; then
    info "Starting docker registry ${REGISTRY_NAME}:${REGISTRY_PORT}"
    mkdir -p ${REGISTRY_STORE}/data
    mkdir -p ${REGISTRY_STORE}/bootstrap
    docker network create --driver bridge kind 2>/dev/null || true
    gen_auth
    docker run -d --restart=always \
              --network "kind" \
              -p "0.0.0.0:${REGISTRY_PORT}:${REGISTRY_INTERNAL_PORT}" \
              ${REGISTRY_CREDENTIALS:+-v "${REGISTRY_STORE}/auth:/auth"} \
              ${REGISTRY_CREDENTIALS:+-e "REGISTRY_AUTH=htpasswd"} \
              ${REGISTRY_CREDENTIALS:+-e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm"} \
              ${REGISTRY_CREDENTIALS:+-e "REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd"} \
              ${REGISTRY_TLS:+-v "${REGISTRY_STORE}/certs:/certs"} \
              ${REGISTRY_TLS:+-e "REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt"} \
              ${REGISTRY_TLS:+-e "REGISTRY_HTTP_TLS_KEY=/certs/domain.key"} \
              -v "${REGISTRY_STORE}/data:/var/lib/registry" \
              --hostname "${REGISTRY_NAME}" \
              --name "local-registry" "${REGISTRY_IMAGE}"
  fi
}

registry_down() {
  echo "Deleting registry '${REGISTRY_NAME}'"
  docker rm -f "local-registry" 2> /dev/null || true
}

# Processes exploded (untarred) helmcharts and pushes them up to the local registry.
# NOTE: Not called anywhere currently
push_exploded_helm_chart() {
  local chart="$1"
  # XXX Working around helm bug with lock file
  rm -f "${chart}/Chart.lock" || true
  helm dependency build "$chart"
  chart_dir=$(mktemp -d)
  # Cleanup after ourselves on exit
  trap_add "rm -rf ${chart_dir}" EXIT INT TERM
  helm package "${chart}" --destination "${chart_dir}"
  push_packaged_helm_chart "${chart_dir}/$(ls "${chart_dir}/")"
}

# Processes tarballed charts and pushes them up to the local registry.
push_packaged_helm_chart() {
  local chart="$1"
  local chart_name
  chart_name="$(helm show chart "${chart}" | yq '.name')"
  info "Pushing to 'oci://localhost:${REGISTRY_PORT}${CHART_REPO}'"
  helm push --insecure-skip-tls-verify "${chart}" "oci://localhost:${REGISTRY_PORT}${CHART_REPO}"
}

# Processes tarballed images and pushes them up to the local registry.
push_docker_tarball() {
  local image_tar="$1"
  manifest_content="$(tar -xOf "${image_tar}" index.json | jq '[.manifests.[].annotations."io.containerd.image.name"]')"
  docker load --input "${image_tar}"
  # Little cleanup trap because I want to be tidy and not leave dangling images
  while IFS= read -r image; do
    trap_add "docker image rm ${image} --force" EXIT INT TERM
  done < <(echo "${manifest_content}" | jq -c '.[]')

  while IFS= read -r image; do
    local registry_image="localhost:${REGISTRY_PORT}${IMAGE_REPO}/${image}"
    info "Pushing '${image}' to '${registry_image}'"
    docker tag "${image}" "${registry_image}"
    trap_add "docker image rm ${registry_image} --force 2>/dev/null" EXIT INT TERM
    docker push "${registry_image}"
  done < <(echo "${manifest_content}" | jq -rc '.[]')
}

# Push contents of tarball as an oci object.
# NOTE: Not finished. Don't know how you want to handle versioning.
#       We could base it on the name of the tarball kind of like how helm names them.
#       It's an exercise I'll leave to the reader. Also, never tested this. It's like 90% of what you want though.
push_oci_artifact(){
  local oci_tar="$1"
  warn "TODO: oci not fully implemented (see script comments), skipping handling $oci_tar."
  return
  local version="0.0.1" # TODO: Implement generic OCI bootstrapping.
  oci_dir=$(mktemp -d)
  # Cleanup after ourselves on exit
  trap_add "rm -rf ${oci_dir}" EXIT INT TERM
  tar -xf "${oci_tar}" -C "${oci_dir}"
  # NOTE: source_artifact probably isn't quite right. I think oras will push the full path to registry
  #       so '/tmp/<mktemp folder>/<untarred file name>' instead of just '<untarred file name>'. Not 100% sure though.
  local source_artifact="${oci_dir}/$(ls "${oci_dir}")"
  local oci_registry="localhost:${REGISTRY_PORT}${OCI_REPO}/$(ls "${oci_dir}")"
  oras push "${oci_registry}" "${source_artifact}"
}

# Does introspection on a tar and pushes it as an appropriate artifact.
process_tar() {
  local source=$1
  if ! tar -tf "${source}" > /dev/null; then
    fatal "Attempting to process tar '${source}' but file is not a valid tar file. Aborting."
  fi
  if helm show chart "${source}" >/dev/null 2>&1; then
    # If a chart.yaml is present, it's a helmchart
    info "Processing helmchart '${source}'"
    push_packaged_helm_chart "${source}"
  elif tar -tf "${source}" manifest.json >/dev/null 2>&1; then
    # If a manifest.yaml is present, it's a tarballed image
    info "Processing docker tarball '${source}'"
    push_docker_tarball "${source}"
  else
    # Else, push as oci
    warn "Tarball ${source} not a recognized helmchart or docker image, skipping"
    # push_oci_artifact "${source}"
  fi
}

# Takes a tar file or a directory containing tar files as an argument and processes them, pushing to a registry.
process_artifact_dir() {
  local source="${1}"
  if [ -e "${source}" ]; then
    for tarball in $(find ${source} -type f); do
      if [ ! -z "${tarball}" ]; then
        process_tar "${tarball}"
      fi
    done
  else
    fatal "Path ${source} not found. Unable to push artifacts to registry. Aborting."
  fi
}

# =======cli handling=======
help() {
  info "$(cat << EOF
Arguments:
  -i    Start registry.
  -s    Stop the running registry.
  -p    Process a directory or tarball, importing all objects into the management.registry.
  -h    Print help documents.
Environment Variables:
  LOG_LEVEL               Set the log level. The following are valid values
                            INFO    Prints only info messages.
                            ERROR   Prints error messages. This is the default log level.
                            DEBUG   Prints error messages, runs this script in debugging mode, and sets verbose on commands it calls.
                            MUTE    Mutes all logging to output
  REGISTRY_NAME           Sets the DNS name of the registry (defaults to 'management.registry'), used in certificate signing.
  REGISTRY_IMAGE          Docker image to use for the registry.
  REGISTRY_PORT           Sets the external registry port (defaults to 5000) that binds on the host.
  REGISTRY_INTERNAL_PORT  Sets the internal registry port (defaults to 5000) used within the registry container.
  REGISTRY_STORE          Path to backing file system (defaults to $HOME/.registry) that will contain persistent registry content.
  INSECURE_REGISTRY       Whether to generate a registry certificate and credentials (defaults to 'true').
  REGISTRY_USER           Username for registry auth (defaults to admin). Stored down $REGISTRY_STORE/auth/htpasswd
  REGISTRY_PSWD           Password for registry auth (defaults to randomized string). Stored down $REGISTRY_STORE/auth/htpasswd
  CHART_REPO              A repo path (defaults to /charts) where helmcharts should be pushed.
  IMAGE_REPO              A repo path (defaults to /images) where docker images should be pushed.
  OCI_REPO                A repo path (defaults to /oci) where oci objects should be pushed.
  PUSH_SOURCE             Either a tarball or a directory containing tarballs of helmcharts, docker images, or oci artifacts.
EOF
)"
}

if (( ${#@} > 0 )); then
  while getopts "p:ish" opt; do
    arg="${OPTARG:-}"
    case $opt in
      p)
        process_artifact_dir "${arg}"
        ;;
      i)
        registry_up
        ;;
      s)
        registry_down
        ;;
      *)
        help
        ;;
    esac
  done
else
  help
  exit 0
fi
