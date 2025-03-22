@echo off

rem Environment variables for WandererNotifier
rem Discord configuration
if not defined DISCORD_BOT_TOKEN set DISCORD_BOT_TOKEN=
if not defined DISCORD_CHANNEL_ID set DISCORD_CHANNEL_ID=

rem Map configuration
if not defined MAP_URL set MAP_URL=
if not defined MAP_NAME set MAP_NAME=
if not defined MAP_TOKEN set MAP_TOKEN=
if not defined MAP_URL_WITH_NAME set MAP_URL_WITH_NAME=

rem Slack configuration
if not defined SLACK_WEBHOOK_URL set SLACK_WEBHOOK_URL=

rem Application configuration
if not defined PORT set PORT=4000
if not defined HOST set HOST=0.0.0.0
if not defined RELEASE_COOKIE set RELEASE_COOKIE=wanderer_notifier_cookie
if not defined RELEASE_NODE set RELEASE_NODE=wanderer_notifier@127.0.0.1

rem Set environment
set MIX_ENV=prod

rem Optional: Set the timezone
if not defined TZ set TZ=UTC 