@echo off

rem Environment variables for Wanderer Notifier
rem This script supports both the legacy and new naming conventions

rem Core Discord configuration
if not defined WANDERER_DISCORD_BOT_TOKEN (
  if defined DISCORD_BOT_TOKEN (
    set WANDERER_DISCORD_BOT_TOKEN=%DISCORD_BOT_TOKEN%
  ) else (
    set WANDERER_DISCORD_BOT_TOKEN=
  )
) else (
  set DISCORD_BOT_TOKEN=%WANDERER_DISCORD_BOT_TOKEN%
)

if not defined WANDERER_DISCORD_CHANNEL_ID (
  if defined DISCORD_CHANNEL_ID (
    set WANDERER_DISCORD_CHANNEL_ID=%DISCORD_CHANNEL_ID%
  ) else (
    set WANDERER_DISCORD_CHANNEL_ID=
  )
) else (
  set DISCORD_CHANNEL_ID=%WANDERER_DISCORD_CHANNEL_ID%
)

rem License configuration
if not defined WANDERER_LICENSE_KEY (
  if defined LICENSE_KEY (
    set WANDERER_LICENSE_KEY=%LICENSE_KEY%
  ) else (
    set WANDERER_LICENSE_KEY=
  )
) else (
  set LICENSE_KEY=%WANDERER_LICENSE_KEY%
)

rem Map configuration
if not defined WANDERER_MAP_URL (
  if defined MAP_URL (
    set WANDERER_MAP_URL=%MAP_URL%
  ) else if defined MAP_URL_WITH_NAME (
    set WANDERER_MAP_URL=%MAP_URL_WITH_NAME%
  ) else (
    set WANDERER_MAP_URL=
  )
) else (
  set MAP_URL=%WANDERER_MAP_URL%
  set MAP_URL_WITH_NAME=%WANDERER_MAP_URL%
)

if not defined WANDERER_MAP_TOKEN (
  if defined MAP_TOKEN (
    set WANDERER_MAP_TOKEN=%MAP_TOKEN%
  ) else (
    set WANDERER_MAP_TOKEN=
  )
) else (
  set MAP_TOKEN=%WANDERER_MAP_TOKEN%
)

rem Web server configuration
if not defined WANDERER_PORT (
  if defined PORT (
    set WANDERER_PORT=%PORT%
  ) else (
    set WANDERER_PORT=4000
  )
) else (
  set PORT=%WANDERER_PORT%
)

if not defined WANDERER_HOST (
  if defined HOST (
    set WANDERER_HOST=%HOST%
  ) else (
    set WANDERER_HOST=0.0.0.0
  )
) else (
  set HOST=%WANDERER_HOST%
)

if not defined WANDERER_SCHEME (
  if defined SCHEME (
    set WANDERER_SCHEME=%SCHEME%
  ) else (
    set WANDERER_SCHEME=http
  )
) else (
  set SCHEME=%WANDERER_SCHEME%
)

rem Database configuration
if not defined WANDERER_DB_USER (
  if defined POSTGRES_USER (
    set WANDERER_DB_USER=%POSTGRES_USER%
  ) else (
    set WANDERER_DB_USER=postgres
  )
) else (
  set POSTGRES_USER=%WANDERER_DB_USER%
)

if not defined WANDERER_DB_PASSWORD (
  if defined POSTGRES_PASSWORD (
    set WANDERER_DB_PASSWORD=%POSTGRES_PASSWORD%
  ) else (
    set WANDERER_DB_PASSWORD=postgres
  )
) else (
  set POSTGRES_PASSWORD=%WANDERER_DB_PASSWORD%
)

if not defined WANDERER_DB_HOST (
  if defined POSTGRES_HOST (
    set WANDERER_DB_HOST=%POSTGRES_HOST%
  ) else (
    set WANDERER_DB_HOST=postgres
  )
) else (
  set POSTGRES_HOST=%WANDERER_DB_HOST%
)

if not defined WANDERER_DB_NAME (
  if defined POSTGRES_DB (
    set WANDERER_DB_NAME=%POSTGRES_DB%
  ) else (
    set WANDERER_DB_NAME=wanderer_notifier
  )
) else (
  set POSTGRES_DB=%WANDERER_DB_NAME%
)

if not defined WANDERER_DB_PORT (
  if defined POSTGRES_PORT (
    set WANDERER_DB_PORT=%POSTGRES_PORT%
  ) else (
    set WANDERER_DB_PORT=5432
  )
) else (
  set POSTGRES_PORT=%WANDERER_DB_PORT%
)

rem Config path for release configuration
set CONFIG_PATH=/app/etc

rem Set environment
set MIX_ENV=prod

rem Optional: Set the timezone
if not defined TZ set TZ=UTC 