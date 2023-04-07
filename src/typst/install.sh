#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

clean_up() {
    rm -rf /var/lib/apt/lists/*
}

apt_get_update() {
    if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
    fi
}

check_packages ca-certificates g++ curl git

export DEBIAN_FRONTEND=noninteractive


# Check if homebrew (linuxbrew) installed.
if ! type brew > /dev/null 2>&1; then
    echo "Installing homebrew..."
    # Borrowed from: https://github.com/meaningful-ooo/devcontainer-features/blob/main/src/homebrew/install.sh
    BREW_PREFIX="/home/linuxbrew/.linuxbrew"
    git clone --depth 1 https://github.com/Homebrew/brew "${BREW_PREFIX}/Homebrew"
    mkdir -p "${BREW_PREFIX}/Homebrew/Library/Taps/homebrew"
    git clone --depth 1 https://github.com/Homebrew/homebrew-core "${BREW_PREFIX}/Homebrew/Library/Taps/homebrew/homebrew-core"

    "${BREW_PREFIX}/Homebrew/bin/brew" config
    mkdir "${BREW_PREFIX}/bin"
    ln -s "${BREW_PREFIX}/Homebrew/bin/brew" "${BREW_PREFIX}/bin"
fi

echo "Installing typst..."

/home/linuxbrew/.linuxbrew/bin/brew install typst
ln -s /home/linuxbrew/.linuxbrew/bin/typst  /usr/local/bin

clean_up
echo "Done!"
