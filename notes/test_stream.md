New Test Results


The test notification is sending sample data, not cached kill data -- please fix


CCP Garthagk (C C P Alliance)
Kill Notification
CCP Garthagk lost a Capsule in Unknown System
Value
150M ISK
Attackers
1
Final Blow
CCP Zoetrope (Avatar)
Alliance
C C P Alliance
Image
Kill ID: 12345678•5/1/2023 8:00 AM


what logic are we using to determine if we send a killmail notification to discord?


also, we should handle this more cleanly -- that's an excessive log message
16:02:23.227 [info] Processed killstream message of type: killmail_with_zkb
16:02:27.981 [warning] zKill websocket disconnected: %{reason: {:remote, :closed}, conn: %WebSockex.Conn{conn_mod: :ssl, host: "zkillboard.com", port: 443, path: "/websocket/", query: nil, extra_headers: [], transport: :ssl, socket: nil, socket_connect_timeout: 6000, socket_recv_timeout: 5000, cacerts: nil, insecure: true, resp_headers: [{"Server-Timing", "cfL4;desc=\"?proto=TCP&rtt=21312&min_rtt=20163&rtt_var=6394&sent=5&recv=7&lost=0&retrans=0&sent_bytes=2806&recv_bytes=597&delivery_rate=136952&cwnd=33&unsent_bytes=0&cid=906b000c811a0702&ts=447&x=0\""}, {"Cf-Ray", "92366ba96bd3804f-JAX"}, {:Server, "cloudflare"}, {"Nel", "{\"success_fraction\":0,\"report_to\":\"cf-nel\",\"max_age\":604800}"}, {"Report-To", "{\"endpoints\":[{\"url\":\"https:\\/\\/a.nel.cloudflare.com\\/report\\/v4?s=6J739r3y6n%2F7frKrktAnGu2menH4OdWq2rdHk42HtxQNzb31iVCLmFlf4%2BeS8YQrkp5ITJTt4GWbqTiG5G1x8hjeP8c2Pnz9Ktw2iz0BZLLVO%2B6%2BhNHduAlw0E1aIGh6\"}],\"group\":\"cf-nel\",\"max_age\":604800}"}, {"Cf-Cache-Status", "DYNAMIC"}, {"Sec-Websocket-Accept", "fbOs1EpaQAh5EqgdUeh/js9rEGk="}, {:Upgrade, "websocket"}, {:Connection, "upgrade"}, {:Date, "Thu, 20 Mar 2025 16:00:07 GMT"}], ssl_options: nil}, attempt_number: 1}. Reconnecting...
16:02:28.557 [info] Connected to zKill websocket.

we still haven't fixed this error
16:04:38.918 [info] Sending startup message...
16:04:38.921 [error] Task #PID<0.456.0> started from #PID<0.301.0> terminating
** (UndefinedFunctionError) function WandererNotifier.Notifiers.Discord.send_embed/6 is undefined or private
    (wanderer_notifier 0.1.0) WandererNotifier.Notifiers.Discord.send_embed("WandererNotifier Started", "The notification service has started successfully.", nil, 3447003, :general, [%{name: "License Status", value: "Valid (Standard)", inline: true}, %{name: "Tracked Systems", value: "19", inline: true}, %{name: "Tracked Characters", value: "134", inline: true}, %{name: "WebSocket Status", value: "Connected (active)", inline: true}, %{name: "Notifications Sent", value: "Total: 0 (Kills: 0, Systems: 0, Characters: 0)", inline: false}, %{name: "Enabled Features", value: "System Tracking, Tracked Characters Notifications, Tracked Systems Notifications, Character Tracking Enabled, Kill Notifications Enabled, Processing All Kills, System Tracking Enabled, Tracking All Systems, Websocket Connected, Basic Notifications, Web Dashboard Basic, License Status Display, Web Dashboard Full", inline: false}])
    (elixir 1.18.2) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2
Function: #Function<4.96255321/0 in WandererNotifier.Application.start/2>
    Args: []
16:04:40.366 [info]

what is the timing of these tasks? i don't see them running after startup

16:04:36.911 [info] Initializing Scheduler Registry...
16:04:36.912 [info] Initializing WandererNotifier.Schedulers.TPSChartScheduler...
16:04:36.917 [info] WandererNotifier.Schedulers.TPSChartScheduler: Scheduled next execution at 2025-03-21 12:00:00Z (in 1195 minutes)
16:04:36.917 [info] WandererNotifier.Schedulers.TPSChartScheduler initialized and scheduled
16:04:36.917 [info] Initializing WandererNotifier.Schedulers.ActivityChartScheduler...
16:04:36.917 [info] WandererNotifier.Schedulers.ActivityChartScheduler initialized and scheduled
16:04:36.917 [info] Initializing WandererNotifier.Schedulers.CharacterUpdateScheduler...
16:04:36.917 [info] WandererNotifier.Schedulers.CharacterUpdateScheduler initialized and scheduled
16:04:36.917 [info] Initializing WandererNotifier.Schedulers.SystemUpdateScheduler...
16:04:36.917 [info] WandererNotifier.Schedulers.SystemUpdateScheduler initialized and scheduled


please provide your answers and next steps in this document