#!/usr/bin/env bash

# updating:
#   Run vis -u, then :Lazy update inside nvim, and quit.
#   cd ~/.config/nvim
#   git status && git diff
#   git commit -am "update plugins"
#   docker tag localhost/nvim-sandbox localhost/nvim-sandbox:prev   # rollback point
#   docker build --build-arg UID=$(id -u) --no-cache -t localhost/nvim-sandbox .

set -euo pipefail

IMAGE="localhost/nvim-sandbox"
CONFIG_SRC="${NVIM_CONFIG_SRC:-$HOME/setup/kickstart.nvim}"

usage() {
    cat >&2 <<'EOF'
usage: vis [-n | -u] [nvim args...]

  (default)  offline, current directory mounted at /work
  -n         allow network access, current directory mounted at /work
  -u         update mode: network on, config repo mounted read-write,
             no project directory mounted

env:
  NVIM_CONFIG_SRC  path to your nvim config repo (default: $HOME/setup/kickstart.nvim)

updating:
  vis -u                                                          # then :Lazy update inside nvim, and quit
  cd ~/.config/nvim                                               # go to the config repo
  git status && git diff                                          # review everything that changed
  git commit -am "update plugins"                                 # commit the new lazy-lock.json
  docker tag localhost/nvim-sandbox localhost/nvim-sandbox:prev   # rollback point
  docker build --build-arg UID=$(id -u) --build-arg TOOLS_REFRESH=$(date +%s) -t localhost/nvim-sandbox .   # rebuild, refreshing Mason tools
EOF
    exit 2
}

network=none
update=0
while getopts ':nuh' opt; do
    case "$opt" in
    n) network=bridge ;;
    u)
        network=bridge
        update=1
        ;;
    h) usage ;;
    *)
        echo "nvim-sandbox: unknown option: -$OPTARG" >&2
        usage
        ;;
    esac
done
shift $((OPTIND - 1))

args=(
    run --rm -it
    --network="$network"
    --cap-drop=ALL
    --security-opt=no-new-privileges
    --pids-limit=512
    -e TERM -e COLORTERM
)

if [[ "$update" == 1 ]]; then
    [[ -f "$CONFIG_SRC/init.lua" ]] || {
        echo "nvim-sandbox: no init.lua in $CONFIG_SRC (set NVIM_CONFIG_SRC)" >&2
        exit 1
    }
    # real config repo mounted rw so lazy-lock.json is written back to the host;
    # no project directory is exposed
    args+=(
        -v "$CONFIG_SRC:/home/dev/.config/nvim:z"
        -w /home/dev/.config/nvim
    )
    echo "nvim-sandbox: UPDATE mode: network ON, writable config at $CONFIG_SRC" >&2
else
    proj="$(pwd -P)"
    args+=(
        -v "$proj:$proj:z"
        -w "$proj"
        -v nvim-state:/home/dev/.local/state/nvim # undo files, shada, logs
    )
    # a compromised plugin could plant git hooks that later run on your host
    [[ -d "$proj/.git/hooks" ]] && args+=(-v "$proj/.git/hooks:/work/.git/hooks:ro,z")
    [[ "$network" == bridge ]] && echo "nvim-sandbox: network ENABLED" >&2
fi

exec sudo docker "${args[@]}" "$IMAGE" "$@"
