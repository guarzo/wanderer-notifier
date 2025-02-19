# Use the latest stable Elixir (Debian-based image)
FROM elixir:1.18-slim

# Install OS dependencies for building Elixir projects and Phoenix hot reload
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential inotify-tools git ca-certificates \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create a non-root user (UID/GID 1000) and set up home directory
RUN groupadd --gid 1000 elixir && \
    useradd --uid 1000 --gid 1000 -m -s /bin/bash elixir

# Set working directory and adjust ownership
WORKDIR /app
RUN chown -R elixir:elixir /app

# Switch to the non-root user
USER elixir

# Install Hex and Rebar for dependency management
RUN mix local.hex --force && mix local.rebar --force

# Expose Phoenix's default port
EXPOSE 4000

# Default command: IEx shell with Mix
CMD ["iex", "-S", "mix"]

