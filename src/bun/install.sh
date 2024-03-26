#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# shellcheck source=/dev/null
source /etc/os-release

# Clean up
cleanup() {
  case "${ID}" in
  debian | ubuntu)
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
  debian | ubuntu)
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
  debian | ubuntu)
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

check_packages curl ca-certificates unzip

# Most of this is from https://bun.sh/install
case $(uname -ms) in
'Darwin x86_64')
    target=darwin-x64
    ;;
'Darwin arm64')
    target=darwin-aarch64
    ;;
'Linux aarch64' | 'Linux arm64')
    target=linux-aarch64
    ;;
'Linux x86_64' | *)
    target=linux-x64
    ;;
esac

if [[ $target = darwin-x64 ]]; then
    # Is this process running in Rosetta?
    # redirect stderr to devnull to avoid error message when not running in Rosetta
    if [[ $(sysctl -n sysctl.proc_translated 2>/dev/null) = 1 ]]; then
        target=darwin-aarch64
        echo "Your shell is running in Rosetta 2. Downloading bun for $target instead"
    fi
fi

GITHUB=${GITHUB-"https://github.com"}

github_repo="$GITHUB/oven-sh/bun"

if [[ $target = darwin-x64 ]]; then
    # If AVX2 isn't supported, use the -baseline build
    if [[ $(sysctl -a | grep machdep.cpu | grep AVX2) == '' ]]; then
        target=darwin-x64-baseline
    fi
fi

if [[ $target = linux-x64 ]]; then
    # If AVX2 isn't supported, use the -baseline build
    if [[ $(cat /proc/cpuinfo | grep avx2) = '' ]]; then
        target=linux-x64-baseline
    fi
fi

exe_name=bun

if [[ $# = 2 && $2 = debug-info ]]; then
    target=$target-profile
    exe_name=bun-profile
    echo "You requested a debug build of bun. More information will be shown if a crash occurs."
fi

if [[ $# = 0 ]]; then
    bun_uri=$github_repo/releases/latest/download/bun-$target.zip
else
    bun_uri=$github_repo/releases/download/$1/bun-$target.zip
fi

install_env=BUN_INSTALL
bin_env=\$$install_env/bin

install_dir="/usr/local"
bin_dir=$install_dir/bin
exe=$bin_dir/bun

if [[ ! -d $bin_dir ]]; then
    mkdir -p "$bin_dir" ||
        echo "Failed to create install directory \"$bin_dir\""
fi

curl --fail --location --progress-bar --output "$exe.zip" "$bun_uri" ||
    echo "Failed to download bun from \"$bun_uri\""

unzip -oqd "$bin_dir" "$exe.zip" ||
    echo 'Failed to extract bun'

mv "$bin_dir/bun-$target/$exe_name" "$exe" ||
    echo 'Failed to move extracted bun to destination'

chmod +x "$exe" ||
    echo 'Failed to set permissions on bun executable'

rm -r "$bin_dir/bun-$target" "$exe.zip"

tildify() {
    if [[ $1 = $HOME/* ]]; then
        local replacement=\~/

        echo "${1/$HOME\//$replacement}"
    else
        echo "$1"
    fi
}

echo "bun was installed successfully to $(tildify "$exe")"

if command -v bun >/dev/null; then
    # Install completions, but we don't care if it fails
    IS_BUN_AUTO_UPDATE=true $exe completions &>/dev/null || :

    echo "Run 'bun --help' to get started"
    exit
fi

refresh_command=''

tilde_bin_dir=$(tildify "$bin_dir")
quoted_install_dir=\"${install_dir//\"/\\\"}\"

if [[ $quoted_install_dir = \"$HOME/* ]]; then
    quoted_install_dir=${quoted_install_dir/$HOME\//\$HOME/}
fi

echo

case $(basename "$SHELL") in
fish)
    # Install completions, but we don't care if it fails
    IS_BUN_AUTO_UPDATE=true SHELL=fish $exe completions &>/dev/null || :

    commands=(
        "set --export $install_env $quoted_install_dir"
        "set --export PATH $bin_env \$PATH"
    )

    fish_config=$HOME/.config/fish/config.fish
    tilde_fish_config=$(tildify "$fish_config")

    if [[ -w $fish_config ]]; then
        {
            echo -e '\n# bun'

            for command in "${commands[@]}"; do
                echo "$command"
            done
        } >>"$fish_config"

        echo "Added \"$tilde_bin_dir\" to \$PATH in \"$tilde_fish_config\""

        refresh_command="source $tilde_fish_config"
    else
        echo "Manually add the directory to $tilde_fish_config (or similar):"

        for command in "${commands[@]}"; do
            echo "  $command"
        done
    fi
    ;;
zsh)
    # Install completions, but we don't care if it fails
    IS_BUN_AUTO_UPDATE=true SHELL=zsh $exe completions &>/dev/null || :

    commands=(
        "export $install_env=$quoted_install_dir"
        "export PATH=\"$bin_env:\$PATH\""
    )

    zsh_config=$HOME/.zshrc
    tilde_zsh_config=$(tildify "$zsh_config")

    if [[ -w $zsh_config ]]; then
        {
            echo -e '\n# bun'

            for command in "${commands[@]}"; do
                echo "$command"
            done
        } >>"$zsh_config"

        echo "Added \"$tilde_bin_dir\" to \$PATH in \"$tilde_zsh_config\""

        refresh_command="exec $SHELL"
    else
        echo "Manually add the directory to $tilde_zsh_config (or similar):"

        for command in "${commands[@]}"; do
            echo "  $command"
        done
    fi
    ;;
bash)
    # Install completions, but we don't care if it fails
    IS_BUN_AUTO_UPDATE=true SHELL=bash $exe completions &>/dev/null || :

    commands=(
        "export $install_env=$quoted_install_dir"
        "export PATH=$bin_env:\$PATH"
    )

    bash_configs=(
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
    )

    if [[ ${XDG_CONFIG_HOME:-} ]]; then
        bash_configs+=(
            "$XDG_CONFIG_HOME/.bash_profile"
            "$XDG_CONFIG_HOME/.bashrc"
            "$XDG_CONFIG_HOME/bash_profile"
            "$XDG_CONFIG_HOME/bashrc"
        )
    fi

    set_manually=true
    for bash_config in "${bash_configs[@]}"; do
        tilde_bash_config=$(tildify "$bash_config")

        if [[ -w $bash_config ]]; then
            {
                echo -e '\n# bun'

                for command in "${commands[@]}"; do
                    echo "$command"
                done
            } >>"$bash_config"

            echo "Added \"$tilde_bin_dir\" to \$PATH in \"$tilde_bash_config\""

            refresh_command="source $bash_config"
            set_manually=false
            break
        fi
    done

    if [[ $set_manually = true ]]; then
        echo "Manually add the directory to $tilde_bash_config (or similar):"

        for command in "${commands[@]}"; do
            echo "  $command"
        done
    fi
    ;;
*)
    echo 'Manually add the directory to ~/.bashrc (or similar):'
    echo "  export $install_env=$quoted_install_dir"
    echo "  export PATH=\"$bin_env:\$PATH\""
    ;;
esac

cleanup

echo "Done!"
