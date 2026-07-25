---
schedule: manual
enabled: true
template: true
title: Export Video Clip
description: "Create a video of your recent screen activity"
icon: "🎬"
featured: false
---

Export a video of my screen activity from the last 5 minutes.

Read screenpipe skill first.

Use the POST /export endpoint (`{"start": "5m ago", "end": "now"}`) — it renders a real-time clip with synced audio whose duration matches the time range. Then show me the returned output_path as an inline code block so I can watch it.

Long ranges can take a few minutes; if needed, suggest a shorter time range.
