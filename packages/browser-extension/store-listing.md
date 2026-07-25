# Chrome Web Store Listing

## Name
Screenpipe Browser Bridge

## Short Description (132 chars max)
Connects your browser to Screenpipe for AI-powered web automation, data sync, and memory capture from authenticated pages.

## Detailed Description
Screenpipe Browser Bridge connects your browser to the Screenpipe desktop app, enabling AI-powered pipes to interact with web pages you're logged into.

HOW IT WORKS
This extension connects to Screenpipe's local server (localhost:3030) via WebSocket. When a Screenpipe pipe needs to read data from a web page, it sends a request through the local server to this extension, which executes it in the browser tab where you're already authenticated.

USE CASES
- Sync your ChatGPT and Claude conversation history into Screenpipe memories
- Extract data from authenticated dashboards and internal tools
- Automate web workflows triggered by your screen activity

PRIVACY & SECURITY
- All communication stays on localhost — no data is sent to external servers
- The extension only activates when Screenpipe's local server is running
- JavaScript execution is triggered only by your local Screenpipe pipes
- No tracking, no analytics, no data collection
- Fully open source: https://github.com/screenpipe/screenpipe

REQUIREMENTS
- Screenpipe desktop app (https://screenpi.pe) running on the same machine
- Works with Chrome, Arc, Brave, Edge, and other Chromium browsers

## Category
Productivity

## Language
English

## Privacy Policy URL
https://screenpi.pe/privacy

## Website
https://screenpi.pe

## Support URL
https://github.com/screenpipe/screenpipe/issues
