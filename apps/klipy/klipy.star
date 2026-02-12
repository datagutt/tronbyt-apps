"""
Applet: Klipy
Summary: Trending & search GIFs
Description: Display trending or search GIFs from the Klipy API. Shows viral/popular GIFs by default, or search for specific GIFs by keyword.
Author: datagutt
"""

load("http.star", "http")
load("random.star", "random")
load("render.star", "render")
load("schema.star", "schema")

KLIPY_BASE = "https://api.klipy.com/api/v1"
LIST_TTL = 1800  # 30 min cache for GIF lists
IMG_TTL = 3600  # 1 hour cache for images
CUSTOMER_ID = "tronbyt-app"

def main(config):
    api_key = config.str("api_key", "")
    search_query = config.str("search_query", "")
    content_filter = config.str("content_filter", "high")

    if api_key == "":
        return render.Root(
            child = render.Box(
                render.Column(
                    expanded = True,
                    main_align = "center",
                    cross_align = "center",
                    children = [
                        render.Text("KLIPY", font = "6x13", color = "#FF6B6B"),
                        render.Text("Set API key", font = "tom-thumb", color = "#888888"),
                    ],
                ),
            ),
        )

    # Build API URL
    if search_query != "":
        url = "%s/%s/gifs/search?q=%s&per_page=10&customer_id=%s&content_filter=%s" % (
            KLIPY_BASE,
            api_key,
            url_encode(search_query),
            CUSTOMER_ID,
            content_filter,
        )
    else:
        url = "%s/%s/gifs/trending?per_page=10&customer_id=%s" % (
            KLIPY_BASE,
            api_key,
            CUSTOMER_ID,
        )

    # Fetch GIF list
    res = http.get(url = url, ttl_seconds = LIST_TTL)
    if res.status_code != 200:
        return render_error("API error: %d" % res.status_code)

    body = res.json()
    if not body.get("result"):
        return render_error("API returned error")

    api_data = body.get("data")
    if not api_data:
        return render_error("No data returned")

    gifs = api_data.get("data", [])
    if len(gifs) == 0:
        return render_error("No GIFs found")

    # Pick a random GIF
    gif = gifs[random.number(0, len(gifs) - 1)]

    # Get image URL
    image_url = extract_image_url(gif.get("file", {}))
    if not image_url:
        return render_error("No image URL")

    # Fetch the actual image
    img_res = http.get(url = image_url, ttl_seconds = IMG_TTL)
    if img_res.status_code != 200:
        return render_error("Image load failed")

    return render.Root(
        child = render.Box(
            child = render.Image(
                src = img_res.body(),
                width = 64,
                height = 32,
            ),
        ),
    )

def extract_image_url(file_obj):
    """Extract the best image URL from the Klipy file object."""
    if not file_obj:
        return None

    # Prefer webp (much smaller download than gif)
    webp = file_obj.get("webp")
    if type(webp) == "dict" and webp.get("url"):
        return webp["url"]

    # Try hd gif
    hd = file_obj.get("hd")
    if type(hd) == "dict":
        gif_fmt = hd.get("gif")
        if type(gif_fmt) == "dict" and gif_fmt.get("url"):
            return gif_fmt["url"]

    # Fallback: try any format that has a url
    for key in file_obj:
        val = file_obj[key]
        if type(val) == "dict":
            if val.get("url"):
                return val["url"]
            for sub_key in val:
                sub_val = val[sub_key]
                if type(sub_val) == "dict" and sub_val.get("url"):
                    return sub_val["url"]

    return None

def url_encode(s):
    """Basic URL encoding for query parameters."""
    s = s.replace("%", "%25")
    s = s.replace(" ", "%20")
    s = s.replace("&", "%26")
    s = s.replace("=", "%3D")
    s = s.replace("+", "%2B")
    s = s.replace("#", "%23")
    s = s.replace("?", "%3F")
    return s

def render_error(msg):
    """Render an error message on screen."""
    return render.Root(
        child = render.Box(
            render.Column(
                expanded = True,
                main_align = "center",
                cross_align = "center",
                children = [
                    render.Text("KLIPY", font = "tom-thumb", color = "#FF6B6B"),
                    render.Marquee(
                        width = 64,
                        child = render.Text(msg, font = "tom-thumb", color = "#FFAA00"),
                    ),
                ],
            ),
        ),
    )

def get_schema():
    content_options = [
        schema.Option(display = "High", value = "high"),
        schema.Option(display = "Medium", value = "medium"),
        schema.Option(display = "Low", value = "low"),
        schema.Option(display = "Off", value = "off"),
    ]

    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "api_key",
                name = "API Key",
                desc = "Your Klipy API key (app_key from docs.klipy.com)",
                icon = "key",
                default = "",
            ),
            schema.Text(
                id = "search_query",
                name = "Search Query",
                desc = "Search for specific GIFs. Leave empty for trending.",
                icon = "magnifyingGlass",
                default = "",
            ),
            schema.Dropdown(
                id = "content_filter",
                name = "Content Filter",
                desc = "Safety filter level for search results.",
                icon = "shield",
                default = "high",
                options = content_options,
            ),
        ],
    )
