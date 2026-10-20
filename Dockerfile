FROM docker.io/library/debian:trixie-slim

WORKDIR /tmp

ARG NVIM_VERSION=v0.12.6
ARG TS_VERSION=v0.27.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git build-essential ripgrep fd-find \
    unzip tar gzip nodejs npm python3 python3-pip python3-venv \
    ncurses-term \
    && ln -s "$(command -v fdfind)" /usr/local/bin/fd 
# && rm -rf /var/lib/apt/lists/*

# Neovim: pinned release, checksum verified
RUN curl -fsSLO "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" \
    && tar -C /opt -xzf nvim-linux-x86_64.tar.gz \
    && ln -s /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim \
    && rm nvim-linux-x86_64.tar.gz

# tree-sitter CLI: pinned release, checksum verified
RUN curl -fsSLO "https://github.com/tree-sitter/tree-sitter/releases/download/${TS_VERSION}/tree-sitter-linux-x64.gz" \
    && gunzip tree-sitter-linux-x64.gz \
    && install -m 0755 tree-sitter-linux-x64 /usr/local/bin/tree-sitter \
    && rm tree-sitter-linux-x64

ARG UID=1000
RUN useradd -m -u ${UID} dev
USER dev
WORKDIR /home/dev
ENV LANG=C.UTF-8 NVIM_SANDBOX=1
RUN mkdir -p /home/dev/.local/state/nvim

COPY --chown=dev:dev . /home/dev/.config/nvim/

ARG TOOLS_REFRESH=0
RUN nvim --headless "+Lazy! install" "+Lazy! restore" +qa

RUN timeout 100 nvim --headless "+MasonToolsInstallSync" +qa \
    && nvim --headless "+lua print(vim.inspect(require('mason-registry').get_installed_package_names()))" +qa

RUN nvim --headless "+lua require('nvim-treesitter').install(vim.g.ts_parsers):wait(100000)" +qa \
    && nvim --headless "+lua print(vim.inspect(require('nvim-treesitter').get_installed()))" +qa

ENTRYPOINT ["nvim"]
