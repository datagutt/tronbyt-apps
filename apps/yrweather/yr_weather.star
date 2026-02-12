"""
Applet: YR Weather
Summary: Weather from YR/MET.no
Description: Animated weather display from the Norwegian Meteorological Institute. Rain, snow, lightning, fog, and cloud animations reflect current conditions. Supports Locationforecast (global) and Nowcast (Nordic area).
Author: datagutt
"""

load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "canvas", "render")
load("schema.star", "schema")

FORECAST_URL = "https://api.met.no/weatherapi/locationforecast/2.0/compact"
NOWCAST_URL = "https://api.met.no/weatherapi/nowcast/2.0/complete"
FORECAST_TTL = 1800  # 30 min
NOWCAST_TTL = 300  # 5 min
USER_AGENT = "TronbytYRWeather/1.0 github.com/tronbyt/apps"
NUM_FRAMES = 24
FRAME_DELAY = 80  # ms per frame

DEFAULT_LOCATION = """
{
	"lat": "59.9139",
	"lng": "10.7522",
	"description": "Oslo, Norway",
	"locality": "Oslo",
	"timezone": "Europe/Oslo"
}
"""

def main(config):
    location = config.get("location", DEFAULT_LOCATION)
    loc = json.decode(location)
    lat = truncate_coord(str(loc.get("lat", "59.9139")))
    lon = truncate_coord(str(loc.get("lng", "10.7522")))
    locality = loc.get("locality", "")

    units = config.str("units", "celsius")
    source = config.str("source", "locationforecast")

    if source == "nowcast":
        base_url = NOWCAST_URL
        ttl = NOWCAST_TTL
    else:
        base_url = FORECAST_URL
        ttl = FORECAST_TTL

    url = "%s?lat=%s&lon=%s" % (base_url, lat, lon)

    res = http.get(
        url = url,
        headers = {"User-Agent": USER_AGENT},
        ttl_seconds = ttl,
    )

    if res.status_code != 200:
        return render_error("API error: %d" % res.status_code)

    body = res.json()
    props = body.get("properties")
    if not props:
        return render_error("No data")

    series = props.get("timeseries", [])
    if len(series) == 0:
        return render_error("No forecast")

    current = series[0]
    instant = current.get("data", {}).get("instant", {}).get("details", {})

    temp_c = instant.get("air_temperature", 0)
    wind = instant.get("wind_speed", 0)

    next_h = current.get("data", {}).get("next_1_hours")
    if not next_h:
        next_h = current.get("data", {}).get("next_6_hours", {})

    symbol = ""
    precip = 0.0
    if next_h:
        symbol = next_h.get("summary", {}).get("symbol_code", "")
        precip = next_h.get("details", {}).get("precipitation_amount", 0.0)

    if units == "fahrenheit":
        temp_val = temp_c * 9.0 / 5.0 + 32.0
        temp_str = "%d°F" % int(temp_val)
    else:
        temp_str = "%d°C" % int(temp_c)

    condition_text, condition_color = get_condition(symbol)
    source_label = "Nowcast" if source == "nowcast" else "Forecast"

    scale = 2 if canvas.is2x() else 1
    w = canvas.width()
    h = canvas.height()
    sm_font = "tom-thumb" if scale == 1 else "terminus-12"
    lg_font = "6x13" if scale == 1 else "terminus-16"

    # Data text overlay
    overlay = render.Column(
        expanded = True,
        main_align = "space_between",
        children = [
            render.Row(
                expanded = True,
                main_align = "space_between",
                children = [
                    render.Text(
                        content = locality if locality else source_label,
                        font = sm_font,
                        color = "#AAAAAA",
                    ),
                    render.Text(
                        content = source_label if locality else "",
                        font = sm_font,
                        color = "#777777",
                    ),
                ],
            ),
            render.Text(content = temp_str, font = lg_font, color = "#FFFFFF"),
            render.Text(content = condition_text, font = sm_font, color = condition_color),
            render.Row(
                expanded = True,
                main_align = "space_between",
                children = [
                    render.Text(content = fmt1(wind) + " m/s", font = sm_font, color = "#BBBBBB"),
                    render.Text(content = fmt1(precip) + " mm", font = sm_font, color = "#6495ED"),
                ],
            ),
        ],
    )

    # Generate weather animation
    weather_type = get_weather_type(symbol)
    bg_frames = make_weather_frames(weather_type, w, h, NUM_FRAMES, scale)

    # Stack animation + dim overlay + text for each frame
    dim = render.Box(width = w, height = h, color = "#00000044")
    children = []
    for frame in bg_frames:
        children.append(render.Stack(children = [frame, dim, overlay]))

    return render.Root(
        delay = FRAME_DELAY,
        child = render.Animation(children = children),
    )

# ---------------------------------------------------------------------------
# Weather lookup tables
# ---------------------------------------------------------------------------

# Exact symbol code -> (display text, color)
CONDITIONS_EXACT = {
    "clearsky": ("Clear sky", "#FFD700"),
    "fair": ("Fair", "#FFE4B5"),
    "partlycloudy": ("Partly cloudy", "#B0B0B0"),
    "cloudy": ("Cloudy", "#808080"),
    "fog": ("Fog", "#696969"),
}

# Substring matches checked in order (first match wins) -> (display text, color)
CONDITIONS_PATTERN = [
    ("thunder", "Thunder", "#FF4500"),
    ("heavysnow", "Heavy snow", "#E8E8FF"),
    ("lightsnow", "Light snow", "#F0F0F0"),
    ("snow", "Snow", "#E8E8E8"),
    ("heavysleet", "Heavy sleet", "#5F9EA0"),
    ("sleet", "Sleet", "#87CEEB"),
    ("heavyrain", "Heavy rain", "#1E3A8A"),
    ("lightrain", "Light rain", "#6495ED"),
    ("rain", "Rain", "#4169E1"),
]

# Exact symbol code -> animation type
ANIM_TYPE_EXACT = {
    "fog": "fog",
    "cloudy": "cloudy",
    "partlycloudy": "cloudy",
    "clearsky": "clear",
    "fair": "clear",
}

# Substring matches checked in order -> animation type
ANIM_TYPE_PATTERN = [
    ("thunder", "thunder"),
    ("snow", "snow"),
    ("sleet", "sleet"),
    ("rain", "rain"),
]

# Animation type -> frame generator function
ANIM_GENERATORS = {
    "rain": lambda w, h, n, s: rain_frames(w, h, n, s),
    "thunder": lambda w, h, n, s: thunder_frames(w, h, n, s),
    "snow": lambda w, h, n, s: snow_frames(w, h, n, s),
    "sleet": lambda w, h, n, s: sleet_frames(w, h, n, s),
    "fog": lambda w, h, n, s: fog_frames(w, h, n, s),
    "cloudy": lambda w, h, n, s: cloud_frames(w, h, n, s),
    "clear": lambda w, h, n, s: clear_frames(w, h, n, s),
}

def strip_time_suffix(symbol_code):
    """Strip _day/_night/_polartwilight suffix from a YR symbol code."""
    code = symbol_code
    for suffix in ["_day", "_night", "_polartwilight"]:
        code = code.replace(suffix, "")
    return code

def get_weather_type(symbol_code):
    """Get simplified weather type for animation selection."""
    code = strip_time_suffix(symbol_code)
    if code in ANIM_TYPE_EXACT:
        return ANIM_TYPE_EXACT[code]
    for pattern, anim_type in ANIM_TYPE_PATTERN:
        if pattern in code:
            return anim_type
    return "default"

def get_condition(symbol_code):
    """Map YR symbol code to display text and color."""
    code = strip_time_suffix(symbol_code)
    if code in CONDITIONS_EXACT:
        return CONDITIONS_EXACT[code]
    for pattern, text, color in CONDITIONS_PATTERN:
        if pattern in code:
            return (text, color)
    if code:
        return (code, "#FFFFFF")
    return ("Unknown", "#FFFFFF")

# ---------------------------------------------------------------------------
# Animation frame generators
# ---------------------------------------------------------------------------

def make_weather_frames(weather_type, w, h, n, scale):
    """Dispatch to the right animation generator via lookup table."""
    generator = ANIM_GENERATORS.get(weather_type)
    if generator:
        return generator(w, h, n, scale)
    return default_frames(w, h, n)

def p(x, y, pw, ph, color):
    """Create a single positioned particle."""
    return render.Padding(
        pad = (x, y, 0, 0),
        child = render.Box(width = pw, height = ph, color = color),
    )

def rain_frames(w, h, n, scale):
    """Multi-layered rain with depth, varying streak lengths, and splashes."""
    s = scale
    frames = []

    # Define rain drop layers: (count, speed, width, height, color, x_offset)
    layers = [
        (8, 1 * s, 1 * s, 3 * s, "#2244AA30", 0),  # back: slow, dim, long
        (12, 2 * s, 1 * s, 2 * s, "#4169E170", 3 * s),  # mid: medium
        (8, 3 * s, 1 * s, 3 * s, "#5B8DEEA0", 1 * s),  # front: fast, bright
    ]

    for f in range(n):
        parts = []

        # Draw each layer
        for count, speed, dw, dh, color, xoff in layers:
            for i in range(count):
                x = (i * (w * 10 // count) // 10 + xoff) % w
                y = (f * speed + i * (h * 10 // 3) // 10) % (h + dh + 2 * s)
                if y <= h - dh:
                    parts.append(p(x, y, dw, dh, color))

                # Splash at bottom: brief bright dot when drop reaches ground
                splash_y = h - 1 * s
                if y >= h - dh and y <= h:
                    parts.append(p(x, splash_y, 2 * s, 1 * s, "#6495ED50"))
                    if x > 0:
                        parts.append(p(x - 1 * s, splash_y, 1 * s, 1 * s, "#4169E130"))
                    if x + 2 * s < w:
                        parts.append(p(x + 2 * s, splash_y, 1 * s, 1 * s, "#4169E130"))

        # Ground puddle shimmer
        shimmer_x = (f * 5 * s) % w
        parts.append(p(shimmer_x, h - 1 * s, 4 * s, 1 * s, "#4169E120"))

        bg = render.Box(width = w, height = h, color = "#04040c")
        frames.append(render.Stack(children = [bg] + parts))
    return frames

def snow_frames(w, h, n, scale):
    """Layered snowfall with varying flake sizes, wobble, and ground buildup."""
    s = scale
    frames = []

    # Flake layers: (count, speed_divisor, size, wobble_range, color)
    layers = [
        (6, 3, 1 * s, 1, "#FFFFFF25"),  # back: tiny, slow, dim
        (10, 2, 1 * s, 2, "#FFFFFF60"),  # mid: normal
        (6, 1, 2 * s, 3, "#FFFFFFA0"),  # front: large, fast, bright
    ]

    for f in range(n):
        parts = []

        # Ground snow buildup (static white bar)
        parts.append(p(0, h - 2 * s, w, 2 * s, "#FFFFFF18"))
        parts.append(p(2 * s, h - 3 * s, 5 * s, 1 * s, "#FFFFFF10"))
        parts.append(p(w - 8 * s, h - 3 * s, 6 * s, 1 * s, "#FFFFFF10"))

        for count, spd, sz, wob, color in layers:
            for i in range(count):
                wobble = ((f // spd + i * 3) % (wob * 2 + 1)) - wob
                x = ((i * (w * 10 // count) // 10 + 2 * s) + wobble * s) % w
                y_raw = f * s // spd + i * (h * 10 // 4) // 10
                y = y_raw % (h + sz)
                if y <= h - sz - 2 * s:
                    parts.append(p(x, y, sz, sz, color))

        bg = render.Box(width = w, height = h, color = "#080814")
        frames.append(render.Stack(children = [bg] + parts))
    return frames

def thunder_frames(w, h, n, scale):
    """Heavy rain with lightning bolts and bright sky flashes."""
    s = scale
    base = rain_frames(w, h, n, s)
    result = []

    # Lightning bolt segments (relative positions for a zigzag bolt)
    bolt_x_base = 12 * s
    bolt_segs = [
        (0, 0, 2 * s, 3 * s),
        (2 * s, 3 * s, 2 * s, 2 * s),
        (-1 * s, 5 * s, 3 * s, 3 * s),
        (1 * s, 8 * s, 2 * s, 2 * s),
        (-2 * s, 10 * s, 2 * s, 4 * s),
    ]
    bolt2_x_base = w - 18 * s
    bolt2_segs = [
        (1 * s, 2 * s, 2 * s, 2 * s),
        (-1 * s, 4 * s, 2 * s, 3 * s),
        (0, 7 * s, 3 * s, 2 * s),
        (2 * s, 9 * s, 2 * s, 3 * s),
    ]

    for f in range(n):
        layers = [base[f]]

        # Flash + bolt at specific frames
        if f in (3, 4, 15, 16):
            bright = "90" if f in (4, 16) else "50"
            layers.append(render.Box(width = w, height = h, color = "#FFFF00" + bright))

            # Draw bolt 1
            bolt_color = "#FFFFFFD0" if f in (4, 16) else "#FFFF8080"
            for dx, dy, bw, bh in bolt_segs:
                bx = bolt_x_base + dx
                if bx >= 0 and bx + bw <= w and dy + bh <= h:
                    layers.append(p(bx, dy, bw, bh, bolt_color))

            # Draw bolt 2 on second flash
            if f in (15, 16):
                for dx, dy, bw, bh in bolt2_segs:
                    bx = bolt2_x_base + dx
                    if bx >= 0 and bx + bw <= w and dy + bh <= h:
                        layers.append(p(bx, dy, bw, bh, bolt_color))

        elif f in (5, 17):
            # Afterglow
            layers.append(render.Box(width = w, height = h, color = "#FFFFFF15"))

        result.append(render.Stack(children = layers))
    return result

def sleet_frames(w, h, n, scale):
    """Dense mix of fast rain streaks and slower drifting snow."""
    s = scale
    frames = []

    for f in range(n):
        parts = []

        # Wet ground
        parts.append(p(0, h - 1 * s, w, 1 * s, "#4169E118"))

        # Rain drops (fast, angled feel via offset x)
        for i in range(10):
            x = (i * (w * 10 // 10) // 10 + (f % 3) * s) % w
            y = (f * 2 * s + i * (h * 10 // 3) // 10) % (h + 3 * s)
            if y <= h - 3 * s:
                parts.append(p(x, y, 1 * s, 3 * s, "#4169E180"))

        # Snow flakes (slow, wobble)
        for i in range(8):
            wobble = ((f + i * 2) % 5) - 2
            x = ((i * (w * 10 // 8) // 10 + 3 * s) + wobble * s) % w
            y = (f * s // 2 + i * (h * 10 // 3) // 10) % (h + 2 * s)
            sz = (2 * s) if i % 3 == 0 else (1 * s)
            if y <= h - sz - 1 * s:
                parts.append(p(x, y, sz, sz, "#FFFFFF70"))

        bg = render.Box(width = w, height = h, color = "#060610")
        frames.append(render.Stack(children = [bg] + parts))
    return frames

def fog_frames(w, h, n, scale):
    """Thick drifting fog bands at multiple heights with pulsing density."""
    s = scale
    frames = []

    # Band definitions: (y_base, height, width_pct, speed, alpha_base)
    bands = [
        (1, 3 * s, 80, 1, 35),
        (7 * s, 4 * s, 70, -1, 28),
        (13 * s, 3 * s, 90, 2, 22),
        (19 * s, 2 * s, 60, -1, 30),
        (24 * s, 3 * s, 75, 1, 25),
        (4 * s, 2 * s, 50, -2, 18),
        (16 * s, 2 * s, 65, 1, 20),
    ]

    for f in range(n):
        parts = []

        for y_base, bh, wpct, spd, alpha_base in bands:
            if y_base + bh > h:
                continue
            bw = w * wpct // 100
            drift = (f * spd * s) // 2
            x = drift % (w + bw) - bw

            # Pulse alpha slightly
            pulse = ((f * 3 + y_base) % 8)
            a = alpha_base + (pulse if pulse < 4 else 8 - pulse) * 3
            ahex = "%02x" % min(a, 255)

            vis_x = max(0, x)
            vis_w = min(bw, w - vis_x)
            if vis_w > 0 and x + bw > 0:
                parts.append(
                    render.Padding(
                        pad = (vis_x, y_base, 0, 0),
                        child = render.Box(width = vis_w, height = bh, color = "#9999AA" + ahex),
                    ),
                )

        bg = render.Box(width = w, height = h, color = "#0c0c12")
        frames.append(render.Stack(children = [bg] + parts))
    return frames

def cloud_frames(w, h, n, scale):
    """Multi-layered clouds with depth and varied shapes."""
    s = scale
    frames = []

    # Cloud definitions: (y, body_w, body_h, speed, alpha, has_bump)
    clouds = [
        (2 * s, 18 * s, 5 * s, 1, "20", True),
        (10 * s, 14 * s, 4 * s, -1, "28", True),
        (18 * s, 20 * s, 5 * s, 2, "18", False),
        (5 * s, 10 * s, 3 * s, -2, "14", False),
        (22 * s, 16 * s, 4 * s, 1, "22", True),
    ]

    for f in range(n):
        parts = []

        for cy, cw, ch, spd, alpha, has_bump in clouds:
            if cy + ch > h:
                continue
            x = ((f * spd * s) // 2 + cy * 3) % (w + cw + 10 * s) - cw - 5 * s
            color = "#8888AA" + alpha

            # Body
            vis_x = max(0, x)
            vis_w = min(cw, w - vis_x)
            if vis_w > 0 and x + cw > 0:
                parts.append(
                    render.Padding(
                        pad = (vis_x, cy, 0, 0),
                        child = render.Box(width = vis_w, height = ch, color = color),
                    ),
                )

            # Top bump (makes it look more cloud-like)
            if has_bump:
                bump_w = cw * 2 // 3
                bump_x = x + cw // 6
                bump_y = cy - ch // 2
                if bump_y >= 0:
                    bvis_x = max(0, bump_x)
                    bvis_w = min(bump_w, w - bvis_x)
                    if bvis_w > 0 and bump_x + bump_w > 0:
                        parts.append(
                            render.Padding(
                                pad = (bvis_x, bump_y, 0, 0),
                                child = render.Box(width = bvis_w, height = ch // 2 + 1, color = color),
                            ),
                        )

        bg = render.Box(width = w, height = h, color = "#08080e")
        frames.append(render.Stack(children = [bg] + parts))
    return frames

def clear_frames(w, h, n, scale):
    """Warm sun with pulsing glow, radiating rays, and golden horizon."""
    s = scale
    sun_r = 4 * s
    sun_x = w - sun_r - 3 * s
    sun_y = 2 * s
    frames = []

    for f in range(n):
        parts = [render.Box(width = w, height = h, color = "#08060a")]

        # Warm horizon glow at bottom
        parts.append(p(0, h - 4 * s, w, 4 * s, "#FF880010"))
        parts.append(p(0, h - 2 * s, w, 2 * s, "#FFAA0018"))

        cycle = f % 12
        if cycle < 6:
            a = 25 + cycle * 8
        else:
            a = 73 - (cycle - 6) * 8

        # Outer glow
        glow_r = sun_r + 4 * s
        parts.append(p(
            max(0, sun_x - 4 * s),
            max(0, sun_y - 4 * s),
            min(glow_r * 2, w - max(0, sun_x - 4 * s)),
            glow_r * 2,
            "#FFD700" + "%02x" % (a // 3),
        ))

        # Mid glow
        mid_r = sun_r + 2 * s
        parts.append(p(
            max(0, sun_x - 2 * s),
            max(0, sun_y - 2 * s),
            min(mid_r * 2, w - max(0, sun_x - 2 * s)),
            mid_r * 2,
            "#FFD700" + "%02x" % (a * 2 // 3),
        ))

        # Sun core
        parts.append(p(sun_x, sun_y, sun_r * 2, sun_r * 2, "#FFD700" + "%02x" % min(a + 30, 200)))

        # Rays extending from sun (4 diagonal directions)
        ray_len = (3 + (cycle % 4)) * s
        ray_color = "#FFD700" + "%02x" % (a // 2)
        cx = sun_x + sun_r
        cy_val = sun_y + sun_r

        # Right ray
        if cx + sun_r < w:
            parts.append(p(cx + sun_r, cy_val, ray_len, 1 * s, ray_color))

        # Down ray
        if cy_val + sun_r < h:
            parts.append(p(cx, cy_val + sun_r, 1 * s, ray_len, ray_color))

        # Diagonal down-right
        for r in range(ray_len // s):
            rx = cx + sun_r + r * s
            ry = cy_val + sun_r + r * s
            if rx < w and ry < h:
                parts.append(p(rx, ry, 1 * s, 1 * s, ray_color))

        # Diagonal down-left
        for r in range(ray_len // s):
            rx = cx - sun_r - r * s
            ry = cy_val + sun_r + r * s
            if rx >= 0 and ry < h:
                parts.append(p(rx, ry, 1 * s, 1 * s, ray_color))

        frames.append(render.Stack(children = parts))
    return frames

def default_frames(w, h, n):
    """Plain dark background."""
    frame = render.Box(width = w, height = h, color = "#0a0a10")
    return [frame] * n

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def fmt1(val):
    """Format a number with 1 decimal place."""
    if val < 0:
        return "-" + fmt1(-val)
    rounded = int(val * 10 + 0.5)
    return "%d.%d" % (rounded // 10, rounded % 10)

def truncate_coord(s):
    """Truncate coordinate to 4 decimal places for MET.no API."""
    parts = s.split(".")
    if len(parts) == 2 and len(parts[1]) > 4:
        return parts[0] + "." + parts[1][:4]
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
                    render.Text("YR", font = "6x13", color = "#4A90D9"),
                    render.Marquee(
                        width = canvas.width(),
                        child = render.Text(msg, font = "tom-thumb", color = "#FFAA00"),
                    ),
                ],
            ),
        ),
    )

def get_schema():
    unit_options = [
        schema.Option(display = "Celsius", value = "celsius"),
        schema.Option(display = "Fahrenheit", value = "fahrenheit"),
    ]

    source_options = [
        schema.Option(display = "Locationforecast (Global)", value = "locationforecast"),
        schema.Option(display = "Nowcast (Nordic only)", value = "nowcast"),
    ]

    return schema.Schema(
        version = "1",
        fields = [
            schema.Location(
                id = "location",
                name = "Location",
                desc = "Location for weather forecast.",
                icon = "locationDot",
            ),
            schema.Dropdown(
                id = "source",
                name = "Data Source",
                desc = "Nowcast gives precise short-term forecasts but only works in the Nordic area.",
                icon = "cloudSunRain",
                default = "locationforecast",
                options = source_options,
            ),
            schema.Dropdown(
                id = "units",
                name = "Temperature",
                desc = "Temperature display units.",
                icon = "temperatureHalf",
                default = "celsius",
                options = unit_options,
            ),
        ],
    )
