# Sandboxed Neovim

This config can run inside a Docker container. The editor, all plugins, all LSP servers, formatters and Treesitter parsers live in one image, and the container runs **without network access** by default. The point is supply-chain containment: a compromised plugin, language server or Mason package can't phone home, and it can only see the project directory you start it in.

The normal host setup (`nvim` with this config) keeps working. Every sandbox-specific change in `init.lua` is guarded by the `NVIM_SANDBOX` environment variable, which only the image sets.

## Contents

- [How it works](#how-it-works)
- [Files](#files)
- [Daily use](#daily-use)
- [Updating](#updating)
- [Changing what's in the image](#changing-whats-in-the-image)
- [Verifying the image](#verifying-the-image)
- [Security model](#security-model)
- [Troubleshooting](#troubleshooting)
- [Known gaps](#known-gaps)

## How it works

Everything that needs the network happens **at build time**:

1. `Lazy! install` + `Lazy! restore` clone every plugin and check it out at the commit in `lazy-lock.json`. Plugin build steps (`make` for telescope-fzf-native and LuaSnip's jsregexp) run here.
2. `MasonToolsInstallSync` installs the language servers and formatters listed in `init.lua`.
3. nvim-treesitter downloads and compiles the parsers listed in `vim.g.ts_parsers`.

At runtime the container starts with `--network=none`, the config baked in, and your project mounted at its real host path. Nothing is fetched, so nothing can be exfiltrated.

## Files

| File | Purpose |
|---|---|
| `Dockerfile` | Debian slim base, Neovim and tree-sitter CLI from GitHub releases, Node/Python for Mason packages, then the three build steps above. |
| `.dockerignore` | Excludes `.git` from the build context. |
| `vis` | Launcher script (kept on your `PATH`). Runs the image with the sandbox flags. |
| `lazy-lock.json` | Must be committed. It is what makes the plugin set reproducible. |

### What `init.lua` does differently inside the sandbox

All of this is gated on `vim.env.NVIM_SANDBOX`, which the Dockerfile sets:

- **`vim.g.ts_parsers`** is the single list of Treesitter parsers. The Dockerfile reads it at build time, and `init.lua` skips its own startup install in the sandbox.
- **Mason**: `mason-tool-installer` has `run_on_start = false` in the sandbox, so it doesn't try the network at launch.
- **Clipboard**: a copy-only OSC 52 provider replaces the host clipboard. `<leader>y` copies to your host clipboard through the terminal. `<leader>p` only pastes what you yanked inside nvim; use your terminal's paste shortcut for host content. This direction is deliberate, because a plugin can overwrite your clipboard but can't read it.

## Daily use

```bash
cd ~/some/project
vis file.lua          # offline, project mounted
vis -n file.lua       # network on (e.g. for fugitive fetch on public remotes)
vis -u                # update mode (see "Updating")
vis -h                # help
```

- The project directory (the directory you run `vis` from) is mounted **read-write at the same absolute path** as on the host. That matters for Python venvs: `.venv` symlinks and the absolute paths inside `.pth` files resolve exactly as they do on the host.
- Start `vis` from a directory that contains everything your project needs. For a workspace of sibling packages, start from the workspace root, not from inside one package. Otherwise editable-install siblings aren't mounted and imports show up as unresolved.
- Extra read-only mounts: `VIS_RO=/path/one:/path/two vis file.py`.
- Undo history, shada and logs persist in the Docker volume `nvim-state`.
- `.git/hooks` of the project is mounted read-only, so a compromised plugin can't plant a hook that later runs on your host.

### Things that do not work offline

- `git push` / `git fetch` from fugitive (no network and no credentials in the container). Do these on the host.
- `:Lazy update`, `:Mason` installs and `:TSInstall` of new parsers. Anything installed in a session is lost on exit (`--rm`). Use the update flow below, or add the item to the config and rebuild.
- `:!make` and other commands only work if the needed tools are in the image.

## Updating

```bash
vis -u                       # network on, config repo mounted writable, no project mounted
                             # inside nvim: :Lazy update, then :q

cd ~/.config/nvim
git status && git diff       # review everything that changed, not just the lockfile
git commit -am "update plugins"

docker tag localhost/nvim-sandbox localhost/nvim-sandbox:prev   # rollback point
docker build --build-arg UID=$(id -u) --build-arg TOOLS_REFRESH=$(date +%s) -t localhost/nvim-sandbox .
```

What this refreshes:

| Component | How it updates |
|---|---|
| Plugins | `:Lazy update` in `vis -u` writes the new commits to `lazy-lock.json`; the rebuild installs exactly those. |
| Treesitter parsers | Revisions follow the nvim-treesitter plugin commit, so they update with the plugins. |
| Mason tools (LSPs, formatters) | Latest registry versions on every rebuild that changes `TOOLS_REFRESH`. |
| Neovim, tree-sitter CLI | Bump the version in the Dockerfile download URLs. |
| apt packages, base image | Only when their layer reruns. Do a `docker build --no-cache` occasionally. |

The review step is the actual supply-chain check. The update session runs freshly downloaded plugin code with network access and write access to the config repo, so look for modified `init.lua` or new files you didn't write. For plugins you care about, open the GitHub compare view between the old and new commit hashes in the lockfile diff.

**Roll back** if something breaks:

```bash
docker tag localhost/nvim-sandbox:prev localhost/nvim-sandbox
```

Clean up old layers afterwards with `docker image prune`.

## Changing what's in the image

**Add a language server or formatter.** Add its Mason package name to the `vim.list_extend(ensure_installed, { ... })` block in `init.lua`, then rebuild.

> Do **not** list a tool there if it's already covered by the `servers` table. `lua_ls` comes from `servers`, so `lua-language-server` must not appear in the extra list. A duplicate made `MasonToolsInstallSync` hang forever during the build.

**Add a Treesitter parser.** Add it to `vim.g.ts_parsers` in `init.lua`, then rebuild. If a language lacks a parser, you only get Neovim's regex highlighting plus a "parser not installed" warning.

**Add system tools** (compilers, Go, other runtimes): add the apt package to the Dockerfile. Tools installed through Mason that need a runtime (npm, pip, `go install`) need that runtime in the image.

**Add or remove plugins**: edit the config as usual, run `:Lazy` in `vis -u` to update the lockfile, review, commit, rebuild.

## Verifying the image

Parsers missing from `vim.g.ts_parsers` (prints only `check done` if everything is present):

```bash
docker run --rm --entrypoint nvim localhost/nvim-sandbox --headless \
  "+lua local have = {} for _, l in ipairs(require('nvim-treesitter').get_installed()) do have[l] = true end for _, l in ipairs(vim.g.ts_parsers) do if not have[l] then print('MISSING: ' .. l) end end print('check done')" +qa
```

Installed Mason packages:

```bash
docker run --rm --entrypoint nvim localhost/nvim-sandbox --headless \
  "+lua print(vim.inspect(require('mason-registry').get_installed_package_names()))" +qa
```

Plugin commits (compare with `lazy-lock.json`):

```bash
docker run --rm --entrypoint bash localhost/nvim-sandbox -c '
  cd ~/.local/share/nvim/lazy && for d in */; do
    printf "%s %s\n" "${d%/}" "$(git -C "$d" rev-parse HEAD)"; done'
```

Sandbox flags, from inside `vis` in a scratch directory:

- `:!curl -m 5 -sI https://github.com` should fail (no network).
- `:!id` should show uid 1000, not root.
- `:!touch .git/hooks/x` should fail (read-only), in a git repo.

## Security model

**What the sandbox protects against**

- Exfiltration: no network by default, so a compromised plugin, LSP or formatter can't send anything out.
- Host access beyond the mounted directory: no `$HOME`, no `~/.ssh`, no cloud credentials, no host clipboard read access.
- Privilege: `--cap-drop=ALL`, `no-new-privileges`, non-root user, PID limit.
- Git hook planting through `.git/hooks`.
- Repo-supplied tooling: a malicious repository's `prettier.config.js` or similar runs inside the sandbox, not on your host.

**What it does not protect against**

- The project directory is writable. A bad plugin can still modify your code, `.git/config` or tracked files such as Makefiles. Review `git diff` after unusual sessions before running or committing anything.
- Network mode (`-n`, `-u`) removes the exfiltration protection for that session. Use them only when needed.
- Update mode runs newly downloaded plugin code with network and a writable config repo. That's what the diff review is for.
- Containers share the host kernel. A kernel-level escape is outside this threat model.
- The build is the trust boundary. `docker build` runs plugin build scripts, Mason installs and downloads with network access.

**Docker specifics**

- The Docker daemon runs as root, and membership in the `docker` group is root-equivalent on the host. Rootless Docker or Podman (same flags) shrinks that risk.
- On Fedora with SELinux, the bind mounts use `:z`, which relabels the mounted directory. Fine for project directories; never mount `$HOME` itself with `:z`.

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| Build hangs at the Mason step | A package is listed twice (see the note under "Changing what's in the image"). The Dockerfile's `timeout` makes the step fail instead of hanging forever. |
| "Permission denied" on project files | Missing `:z` on the mount (SELinux), or the image's `UID` doesn't match yours. Rebuild with `--build-arg UID=$(id -u)`. |
| Unresolved Python imports | The project isn't mounted at its real path, or the sibling packages aren't mounted. Start `vis` from the workspace root and use `VIS_RO` for anything outside it. Set `pythonVersion` in `[tool.pyright]`, since the venv's interpreter symlink points at a host path that doesn't exist in the container. |
| "Treesitter parser for X not installed" | Add it to `vim.g.ts_parsers` and rebuild. |
| Formatter does nothing | It isn't in the image. `notify_on_error = false` hides the failure; `:ConformInfo` shows what was found. Add it to the Mason list and rebuild. |
| `<leader>y` doesn't reach the host clipboard | Your terminal must allow OSC 52 writes. Under tmux, set `set -g set-clipboard on`. |
| `gopls` or other servers need modules/downloads | They can't fetch offline. Run `vis -n` once to populate caches (they vanish with the container unless a volume is added) or install the dependencies on the host and mount them. |
| Something broke after a rebuild | Roll back with `docker tag localhost/nvim-sandbox:prev localhost/nvim-sandbox`. |

## Known gaps

- **Mason tool versions float.** Every rebuild installs the latest registry versions. Only plugins are pinned (by `lazy-lock.json`).
- **lazy.nvim itself** is cloned from its `stable` branch during bootstrap and may not match the commit in the lockfile.
- **apt packages are not pinned**, and the Neovim and tree-sitter CLI downloads are only as trustworthy as the GitHub release they come from. Add checksum verification to the Dockerfile if you want that gap closed.
- **Mason runs install scripts for npm/pip packages** during the build, as far as I know. The build is where that trust is spent, which is why the runtime is offline.
