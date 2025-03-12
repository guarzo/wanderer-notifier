# Use a Debian-based Elixir image (NOT the alpine variant).
FROM elixir:1.18.2-slim

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
    vim \
    nettools \
    # Optionally add any other tools you need, e.g. vim, wget...
    && curl -sL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y --no-install-recommends nodejs inotify-tools \
    && npm install -g yarn \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user named "elixir"
RUN useradd -ms /bin/bash elixir

# Give the "elixir" user passwordless sudo
RUN usermod -aG sudo elixir && \
    echo "elixir ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set a working directory (your choice)
WORKDIR /workspace

# Switch to the non-root user by default
USER elixir

# (Optional) If you want to install Hex/Rebar global for the container, uncomment:
# RUN mix local.hex --force && mix local.rebar --force

# Leaving CMD/ENTRYPOINT unset here so you can specify the run command externally.
