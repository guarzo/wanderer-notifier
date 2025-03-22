FROM elixir:otp-27

# Define ARGs for customization
ARG USERNAME=elixir
ARG NODE_VERSION=20.x
ARG INSTALL_ELIXIR_LS=true

# Install OS packages and Node.js (via nodesource),
# plus inotify-tools and yarn
RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    curl \
    make \
    git \
    bash \
    build-essential \
    ca-certificates \
    jq \
    vim \
    net-tools \
    procps \
    zsh \
    unzip \
    gnupg \
    # Optionally add any other tools you need, e.g. vim, wget...
    && curl -sL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - \
    && apt-get install -y --no-install-recommends nodejs inotify-tools \
    && npm install -g yarn \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user with the USERNAME arg
RUN useradd -ms /bin/bash ${USERNAME}

# Give the user passwordless sudo
RUN usermod -aG sudo ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R ${USERNAME} /commandhistory

# Set `DEVCONTAINER` environment variable to help with orientation
ENV DEVCONTAINER=true

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/${USERNAME}/.claude && \
  chown -R ${USERNAME}:${USERNAME} /workspace /home/${USERNAME}/.claude

# Set a working directory (your choice)
WORKDIR /workspace

# Switch to the non-root user by default
USER ${USERNAME}

# Install global packages
ENV NPM_CONFIG_PREFIX=/home/${USERNAME}/.npm-global
ENV PATH=$PATH:/home/${USERNAME}/.npm-global/bin

# Set the default shell to zsh rather than sh
ENV SHELL /bin/zsh

# Create global npm directory with correct permissions
RUN mkdir -p /home/${USERNAME}/.npm-global && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.npm-global

RUN npm install -g @anthropic-ai/claude-code

# Install Hex/Rebar global for the container
RUN mix local.hex --force && mix local.rebar --force

# Install Credo for linting
RUN mix archive.install --force hex credo

# Install ElixirLS if enabled
RUN if [ "$INSTALL_ELIXIR_LS" = "true" ]; then \
    mkdir -p /home/${USERNAME}/.elixir-ls && \
    cd /home/${USERNAME}/.elixir-ls && \
    git clone --depth=1 https://github.com/elixir-lsp/elixir-ls.git . && \
    mix deps.get && \
    mix compile && \
    mix elixir_ls.release2 -o /home/${USERNAME}/.elixir-ls/release && \
    chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.elixir-ls; \
    fi

# Leaving CMD/ENTRYPOINT unset here so you can specify the run command externally.
