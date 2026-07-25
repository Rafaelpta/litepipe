# Screenpipe Browser Bridge

Chrome/Chromium extension that connects your browser to Screenpipe, enabling pipes to execute JavaScript in browser tabs.

## How it works

1. Extension connects to Screenpipe's local server via WebSocket (`ws://localhost:3030/browser/ws`)
2. Pipes send JS code via `POST /browser/eval`
3. Extension executes the code in the matching tab using `chrome.scripting.executeScript`
4. Results flow back through the same path

## Development

```bash
bun install
bun run build    # one-shot build
bun run dev      # watch mode
```

Load the extension in Chrome:
1. Go to `chrome://extensions`
2. Enable "Developer mode"
3. Click "Load unpacked" → select the `dist/` folder

## API

### `POST /browser/eval`

Execute JavaScript in a browser tab.

```json
{
  "code": "return document.title",
  "url": "chatgpt.com"  // optional: run in a tab matching this URL
}
```

Response:
```json
{
  "success": true,
  "result": "ChatGPT"
}
```

## Use cases

- Sync ChatGPT/Claude conversation history into Screenpipe memories
- Scrape authenticated web pages (uses the browser's own cookies)
- Automate web workflows from pipes
