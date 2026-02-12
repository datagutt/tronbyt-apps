# Klipy GIFs

Display trending or search GIFs from the [Klipy API](https://docs.klipy.com/gifs-api) on your Tronbyt/Tidbyt.

![Preview](klipy.webp) ![Preview 2x](klipy@2x.webp)

## Features

- **Trending mode** (default) - cycles through the most popular/viral GIFs
- **Search mode** - enter a keyword to search for specific GIFs
- **Content filter** - configurable safety level (High, Medium, Low, Off)
- Prefers WebP format for smaller downloads on the constrained display
- Picks a random GIF each render cycle from the cached result set
- Official Klipy logo attribution bar
- 2x display support

## Configuration

| Field | Description |
|---|---|
| **API Key** | Your Klipy `app_key` from [docs.klipy.com](https://docs.klipy.com) |
| **Search KLIPY** | Search query. Leave empty for trending GIFs |
| **Content Filter** | Safety filter level for results |

## Usage

```sh
# Render with default (no API key - shows placeholder)
pixlet render apps/klipy/klipy.star

# Render with API key (trending)
pixlet render apps/klipy/klipy.star api_key=YOUR_KEY

# Render with search
pixlet render apps/klipy/klipy.star api_key=YOUR_KEY search_query="funny cats"

# Live preview
pixlet serve apps/klipy/klipy.star
```

## Attribution

Powered by KLIPY. Per [API usage guidelines](https://docs.klipy.com/gifs-api), this app displays visible "Powered by KLIPY" branding and uses "Search KLIPY" as the search field name.
