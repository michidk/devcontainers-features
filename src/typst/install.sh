#!/bin/bash

# inspired by https://github.com/guiyomh/features/blob/main/src/just/install.sh
TYPST_VERSION=${VERSION:-"latest"}
set -e

# shellcheck source=/dev/null
source /etc/os-release

# Clean up
cleanup() {
case "${ID}" in
    debian|ubuntu)
      rm -rf /var/lib/apt/lists/*
    ;;
  esac
}

cleanup

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

apt_get_update() {
  case "${ID}" in
    debian|ubuntu)
      if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
      fi
    ;;
  esac
}

# Checks if packages are installed and installs them if not
check_packages() {
  case "${ID}" in
    debian|ubuntu)
      if ! dpkg -s "$@" >/dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
      fi
    ;;
    alpine)
      if ! apk -e info "$@" >/dev/null 2>&1; then
        apk add --no-cache "$@"
      fi
    ;;
  esac
}

check_git() {
    if [ ! -x "$(command -v git)" ]; then
        check_packages git
    fi
}

find_version_from_git_tags() {
    local variable_name=$1
    local requested_version=${!variable_name}
    if [ "${requested_version}" = "none" ]; then return; fi
    local repository=$2
    local prefix=${3:-"tags/v"}
    local separator=${4:-"."}
    local last_part_optional=${5:-"false"}
    if [ "$(echo "${requested_version}" | grep -o "." | wc -l)" != "2" ]; then
        local escaped_separator=${separator//./\\.}
        local last_part
        if [ "${last_part_optional}" = "true" ]; then
            last_part="(${escaped_separator}[0-9]+)*?"
        else
            last_part="${escaped_separator}[0-9]+"
        fi
        local regex="${prefix}\\K[0-9]+${escaped_separator}[0-9]+${last_part}$"
        local version_list
        check_git
        check_packages ca-certificates
        version_list="$(git ls-remote --tags "${repository}" | grep -oP "${regex}" | tr -d ' ' | tr "${separator}" "." | sort -rV)"
        if [ "${requested_version}" = "latest" ] || [ "${requested_version}" = "current" ] || [ "${requested_version}" = "lts" ]; then
            declare -g "${variable_name}"="$(echo "${version_list}" | head -n 1)"
        else
            set +e
            declare -g "${variable_name}"="$(echo "${version_list}" | grep -E -m 1 "^${requested_version//./\\.}([\\.\\s]|$)")"
            set -e
        fi
    fi
    if [ -z "${!variable_name}" ] || ! echo "${version_list}" | grep "^${!variable_name//./\\.}$" >/dev/null 2>&1; then
        echo -e "Invalid ${variable_name} value: ${requested_version}\nValid values:\n${version_list}" >&2
        exit 1
    fi
    echo "${variable_name}=${!variable_name}"
}

# https://www.baeldung.com/linux/check-variable-exists-in-list
function exists_in_list() {
    LIST=$1
    DELIMITER=$2
    VALUE=$3
    LIST_WHITESPACES=`echo $LIST | tr "$DELIMITER" " "`
    for x in $LIST_WHITESPACES; do
        if [ "$x" = "$VALUE" ]; then
            return 0
        fi
    done
    return 1
}

export DEBIAN_FRONTEND=noninteractive

check_packages dpkg xz-utils

# supported architectures in version 0.3.0 and beyond (with musl)
# Before 0.3.0, typst only supports x86_64
SUPPORTED_ARCHS="aarch64 x86_64"

architecture="$(uname -m)"

# check if the version starts with 0.2 or 0.1 ("older" versions)
# https://stackoverflow.com/a/2172367
if [[ $TYPST_VERSION == '0.2.'* ]] || [[ $TYPST_VERSION == '0.1.'* ]]; then
    if [[ "${architecture}" != "x86_64" ]]; then
        echo "(!) Architecture $architecture unsupported for older Typst version v$TYPST_VERSION!"
        exit 1
    fi
    # typst only supports gnu libc for v0.1 and 0.2
    # Also, for these versions, the extension is `tar.gz`
    LIBC="gnu"
    EXTENSION="tar.gz"
# check support for "newer" versions
elif ! exists_in_list "$SUPPORTED_ARCHS" " " $architecture; then
    echo "(!) Architecture $architecture unsupported for Typst version v$TYPST_VERSION!"
    exit 1
else
    echo "Your platform architecture is supported by Typst version v$TYPST_VERSION!"
    # (at least for version 0.3-0.5), typst uses musl, with `tar.xz` extension
    LIBC="musl"
    EXTENSION="tar.xz"
fi

# Soft version matching
find_version_from_git_tags TYPST_VERSION "https://github.com/typst/typst"

check_packages curl ca-certificates
echo "Downloading typst version ${TYPST_VERSION}..."

mkdir -p /tmp/typst
BIN_PATH="/tmp/typst-v${TYPST_VERSION}-${architecture}-${LIBC}-${EXTENSION}"
curl -sL "https://github.com/typst/typst/releases/download/v${TYPST_VERSION}/typst-${architecture}-unknown-linux-${LIBC}.${EXTENSION}" -o "$BIN_PATH"

# we need tar extraction commands for the different extensions
if [ $EXTENSION = "tar.gz" ]; then
    tar xfz "$BIN_PATH" -C /tmp/typst
else
    tar xfJ "$BIN_PATH" -C /tmp/typst
fi

mv "/tmp/typst/typst-$(uname -m)-unknown-linux-${LIBC}/typst" /usr/local/bin/typst
rm -rf /tmp/typst

# Clean up
cleanup

echo "Done!"
