# ChainKills

ChainKills is an Elixir-based application that monitors EVE Online kill data and notifies designated Discord channels about significant events. It integrates with multiple external services to retrieve, enrich, and filter kill information before sending alerts.

## Features

- **Real-Time Monitoring:** Listens to live kill data via a WebSocket from ZKillboard.
- **Data Enrichment:** Retrieves detailed killmail information from ESI.
- **Map-Based Filtering:** Uses a custom map API to track wormhole systems and process only those kills originating from systems you care about.
- **Periodic Maintenance:** Automatically updates system data, processes backup kills, and sends heartbeat notifications to Discord.
- **Caching:** Implements caching with Cachex to minimize redundant API calls.
- **Fault Tolerance:** Leverages Elixir’s OTP and supervision trees to ensure a robust and resilient system.

## Requirements

- Elixir (>= 1.12 recommended)
- Erlang/OTP (compatible version)
- [Docker](https://www.docker.com/) (optional, for development container)

## Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/yourusername/chainkills.git
   cd chainkills
   ```

2. **Setup Environment Variables:**

   Create a `.env` file (you can use the provided `.env.example` as a template):

   ```dotenv
   DISCORD_BOT_TOKEN=your_discord_bot_token
   MAP_URL=https://wanderer.zoolanders.space
   MAP_NAME=your_map_slug
   MAP_TOKEN=your_map_api_token
   DISCORD_CHANNEL_ID=your_discord_channel_id
   ZKILL_BASE_URL=https://zkillboard.com
   ESI_BASE_URL=https://esi.evetech.net/latest
   ```

3. **Install Dependencies:**

   Using the provided Makefile, run:

   ```bash
   make deps.get
   ```

4. **Compile the Project:**

   ```bash
   make compile
   ```

## Running the Application

You can run the application in several ways:

- **Interactive Shell:**

  ```bash
  make shell
  ```

- **Run the Application:**

  ```bash
  make run
  ```

- **Directly via Mix:**

  ```bash
  mix run --no-halt
  ```

## Development

### Using the Dev Container

This project includes a development container configuration for VS Code:

1. Install the [Remote - Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) for VS Code.
2. Open the repository in VS Code.
3. When prompted, reopen the project in the container. The container is configured using the included `devcontainer.json` and `Dockerfile`.
4. The container automatically runs `mix deps.get` upon setup.

### Makefile Commands

The Makefile provides shortcuts for common tasks:

- **Compile:** `make compile`
- **Clean:** `make clean`
- **Test:** `make test`
- **Format:** `make format`
- **Interactive Shell:** `make shell`
- **Run Application:** `make run`
- **Get Dependencies:** `make deps.get`
- **Update Dependencies:** `make deps.update`

## Configuration

All configuration is managed through environment variables in the `.env` file. A template is provided as `.env.example`.



---

*ChainKills* integrates critical EVE Online data with Discord notifications in a robust, fault-tolerant manner. For any questions or issues, please open an issue on the repository.
