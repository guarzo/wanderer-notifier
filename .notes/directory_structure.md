# Project Directory Structure

This document provides an overview of the project's directory structure, focusing on user-written code and excluding dependencies and build artifacts.

## Legend
- 🟣 Elixir (*.ex, *.exs)
- 🟪 Elixir Templates (*.eex, *.heex)
- 🟨 JavaScript (*.js, *.jsx)
- 🔵 TypeScript (*.ts, *.tsx)
- 🐹 Go (*.go)
- 🎨 Stylesheets (*.css, *.scss)
- 📋 JSON/Templates (*.json, templates)
- 📝 Markdown (*.md)
- 🌐 HTML (*.html, *.htm)
- 💾 SQL (*.sql)
- 🐚 Shell Scripts (*.sh, *.bash)
- ⚙️ Configuration (*.yml, *.yaml, config)
- 📄 Other Files

## Core Components

```
- ⚙️ **config/**
    - 🟣 config.exs
    - 🟣 dev.exs
    - 🟣 prod.exs
    - 🟣 runtime.exs
    - 🟣 test.exs
- 📚 **lib/**
    - 📁 **wanderer_notifier/**
        - 📁 **cache/**
            - 🟣 repository.ex
        - ⚙️ **config/**
            - 🟣 timings.ex
        - 📁 **discord/**
            - 🟣 notifier.ex
            - 🟣 test_notifier.ex
        - 📁 **esi/**
            - 🟣 client.ex
            - 🟣 service.ex
        - 📁 **helpers/**
            - 🟣 cache_helpers.ex
        - 📁 **http/**
            - 🟣 client.ex
            - 🟣 response_handler.ex
        - 📁 **license_manager/**
            - 🟣 client.ex
        - 📁 **maintenance/**
            - 🟣 scheduler.ex
        - 📁 **map/**
            - 🟣 backup_kills.ex
            - 🟣 characters.ex
            - 🟣 client.ex
            - 🟣 systems.ex
        - 📁 **service/**
            - 🟣 kill_processor.ex
            - 🟣 maintenance.ex
            - 🟣 service.ex
        - 📁 **slack/**
            - 🟣 notifier.ex
        - 📁 **web/**
            - 🟣 router.ex
            - 🟣 server.ex
        - 📁 **zkill/**
            - 🟣 client.ex
            - 🟣 service.ex
            - 🟣 websocket.ex
        - 🟣 client.ex
        - 🟣 service.ex
        - 🟣 websocket.ex
    - 🟣 client.ex
    - 🟣 service.ex
    - 🟣 websocket.ex
```

## Note
This structure was automatically generated and may not include all files. Directories and files that are typically not user code (build artifacts, dependencies, etc.) have been excluded. The structure is limited to a depth of 4 levels and shows at most 15 files per directory.

