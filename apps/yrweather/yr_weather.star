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
NUM_FRAMES = 48
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

    # Debug override: force a specific animation and matching label
    debug_anim = config.str("debug_anim", "none")
    if debug_anim and debug_anim != "none":
        condition_text, condition_color = CONDITIONS.get(debug_anim, (debug_anim, "#FFFFFF"))

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
    weather_type = get_weather_type(debug_anim) if (debug_anim and debug_anim != "none") else get_weather_type(symbol)
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

# Complete symbol code -> (display text, color)
# All 41 symbols from https://api.met.no/weatherapi/weathericon/2.0
CONDITIONS = {
    # Base conditions
    "clearsky": ("Clear sky", "#FFD700"),
    "fair": ("Fair", "#FFE4B5"),
    "partlycloudy": ("Partly cloudy", "#B0B0B0"),
    "cloudy": ("Cloudy", "#808080"),
    "fog": ("Fog", "#696969"),
    # Rain
    "lightrain": ("Light rain", "#6495ED"),
    "rain": ("Rain", "#4169E1"),
    "heavyrain": ("Heavy rain", "#1E3A8A"),
    # Rain showers
    "lightrainshowers": ("Lt rain shwrs", "#6495ED"),
    "rainshowers": ("Rain showers", "#4169E1"),
    "heavyrainshowers": ("Hvy rain shwrs", "#1E3A8A"),
    # Rain + thunder
    "lightrainandthunder": ("Lt rain+thndr", "#FF6347"),
    "rainandthunder": ("Rain+thunder", "#FF4500"),
    "heavyrainandthunder": ("Hvy rain+thndr", "#DC143C"),
    # Rain showers + thunder
    "lightrainshowersandthunder": ("Lt shwrs+thndr", "#FF6347"),
    "rainshowersandthunder": ("Shwrs+thunder", "#FF4500"),
    "heavyrainshowersandthunder": ("Hvy shwrs+thdr", "#DC143C"),
    # Sleet
    "lightsleet": ("Light sleet", "#87CEEB"),
    "sleet": ("Sleet", "#87CEEB"),
    "heavysleet": ("Heavy sleet", "#5F9EA0"),
    # Sleet showers
    "lightsleetshowers": ("Lt sleet shwrs", "#87CEEB"),
    "sleetshowers": ("Sleet showers", "#87CEEB"),
    "heavysleetshowers": ("Hvy sleet shwr", "#5F9EA0"),
    # Sleet + thunder
    "lightsleetandthunder": ("Lt sleet+thndr", "#FF6347"),
    "sleetandthunder": ("Sleet+thunder", "#FF4500"),
    "heavysleetandthunder": ("Hvy slt+thndr", "#DC143C"),
    # Sleet showers + thunder
    "lightssleetshowersandthunder": ("Lt slt shr+thr", "#FF6347"),
    "sleetshowersandthunder": ("Slt shwrs+thdr", "#FF4500"),
    "heavysleetshowersandthunder": ("Hvy slt sh+thr", "#DC143C"),
    # Snow
    "lightsnow": ("Light snow", "#F0F0F0"),
    "snow": ("Snow", "#E8E8E8"),
    "heavysnow": ("Heavy snow", "#E8E8FF"),
    # Snow showers
    "lightsnowshowers": ("Lt snow shwrs", "#F0F0F0"),
    "snowshowers": ("Snow showers", "#E8E8E8"),
    "heavysnowshowers": ("Hvy snow shwrs", "#E8E8FF"),
    # Snow + thunder
    "lightsnowandthunder": ("Lt snow+thndr", "#FF6347"),
    "snowandthunder": ("Snow+thunder", "#FF4500"),
    "heavysnowandthunder": ("Hvy snow+thndr", "#DC143C"),
    # Snow showers + thunder
    "lightssnowshowersandthunder": ("Lt snw shr+thr", "#FF6347"),
    "snowshowersandthunder": ("Snw shwrs+thdr", "#FF4500"),
    "heavysnowshowersandthunder": ("Hvy snw sh+thr", "#DC143C"),
}

# Ordered list for schema dropdown
CONDITIONS_KEYS = [
    "clearsky",
    "fair",
    "partlycloudy",
    "cloudy",
    "fog",
    "lightrain",
    "rain",
    "heavyrain",
    "lightrainshowers",
    "rainshowers",
    "heavyrainshowers",
    "lightrainandthunder",
    "rainandthunder",
    "heavyrainandthunder",
    "lightrainshowersandthunder",
    "rainshowersandthunder",
    "heavyrainshowersandthunder",
    "lightsleet",
    "sleet",
    "heavysleet",
    "lightsleetshowers",
    "sleetshowers",
    "heavysleetshowers",
    "lightsleetandthunder",
    "sleetandthunder",
    "heavysleetandthunder",
    "lightssleetshowersandthunder",
    "sleetshowersandthunder",
    "heavysleetshowersandthunder",
    "lightsnow",
    "snow",
    "heavysnow",
    "lightsnowshowers",
    "snowshowers",
    "heavysnowshowers",
    "lightsnowandthunder",
    "snowandthunder",
    "heavysnowandthunder",
    "lightssnowshowersandthunder",
    "snowshowersandthunder",
    "heavysnowshowersandthunder",
]

# Complete symbol code -> animation type
ANIM_TYPES = {
    "clearsky": "clear",
    "fair": "clear",
    "partlycloudy": "cloudy",
    "cloudy": "cloudy",
    "fog": "fog",
    # Rain
    "lightrain": "rain",
    "rain": "rain",
    "heavyrain": "rain",
    "lightrainshowers": "rain",
    "rainshowers": "rain",
    "heavyrainshowers": "rain",
    # Rain + thunder
    "lightrainandthunder": "thunder",
    "rainandthunder": "thunder",
    "heavyrainandthunder": "thunder",
    "lightrainshowersandthunder": "thunder",
    "rainshowersandthunder": "thunder",
    "heavyrainshowersandthunder": "thunder",
    # Sleet
    "lightsleet": "sleet",
    "sleet": "sleet",
    "heavysleet": "sleet",
    "lightsleetshowers": "sleet",
    "sleetshowers": "sleet",
    "heavysleetshowers": "sleet",
    # Sleet + thunder
    "lightsleetandthunder": "thunder",
    "sleetandthunder": "thunder",
    "heavysleetandthunder": "thunder",
    "lightssleetshowersandthunder": "thunder",
    "sleetshowersandthunder": "thunder",
    "heavysleetshowersandthunder": "thunder",
    # Snow
    "lightsnow": "snow",
    "snow": "snow",
    "heavysnow": "snow",
    "lightsnowshowers": "snow",
    "snowshowers": "snow",
    "heavysnowshowers": "snow",
    # Snow + thunder
    "lightsnowandthunder": "thunder",
    "snowandthunder": "thunder",
    "heavysnowandthunder": "thunder",
    "lightssnowshowersandthunder": "thunder",
    "snowshowersandthunder": "thunder",
    "heavysnowshowersandthunder": "thunder",
}

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
    return ANIM_TYPES.get(code, "default")

def get_condition(symbol_code):
    """Map YR symbol code to display text and color."""
    code = strip_time_suffix(symbol_code)
    if code in CONDITIONS:
        return CONDITIONS[code]
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

def gcd(a, b):
    """Greatest common divisor (Euclidean algorithm)."""
    a, b = max(1, abs(a)), max(0, abs(b))
    for _ in range(64):
        if b == 0:
            break
        a, b = b, a % b
    return a

def loop_cycle(raw_cycle, speed, n):
    """Round raw_cycle up so that cycle * speed is divisible by n.

    When cycle * speed % n != 0, loop_pos produces an uneven step at the
    animation boundary (the gap between frame n-1 and frame 0 differs from
    other inter-frame gaps).  Snapping the cycle to the next valid value
    eliminates this, guaranteeing perfectly uniform motion across the loop
    point.

    Always compute the cycle with this function BEFORE passing it to
    loop_pos so that phase offsets (e.g. i * cycle // count) are also
    based on the snapped value.
    """
    abs_speed = max(1, abs(speed))
    step = n // gcd(n, abs_speed)
    if raw_cycle <= step:
        return step
    return ((raw_cycle + step - 1) // step) * step

def loop_pos(f, n, cycle, speed, phase):
    """Compute position that seamlessly loops over n frames.

    speed = number of complete cycles per n frames.
    Returns value in [0, cycle).

    IMPORTANT: pass cycle through loop_cycle() first to guarantee that
    cycle * speed is divisible by n.  Otherwise the step from frame n-1
    back to frame 0 will differ from other inter-frame steps, producing a
    visible hitch at the loop boundary.
    """
    return (f * cycle * speed // n + phase) % cycle

def rain_frames(w, h, n, scale):
    """Multi-layered rain with depth, varying streak lengths, and splashes."""
    s = scale
    frames = []

    # (count, speed_mult, width, height, color, x_offset)
    # speed_mult = complete fall cycles per animation loop
    layers = [
        (8, 1, 1 * s, 3 * s, "#2244AA30", 0),  # back: slow, dim, long
        (12, 2, 1 * s, 2 * s, "#4169E170", 3 * s),  # mid: medium
        (8, 3, 1 * s, 3 * s, "#5B8DEEA0", 1 * s),  # front: fast, bright
    ]

    for f in range(n):
        parts = []

        # Draw each layer
        for count, spd, dw, dh, color, xoff in layers:
            cycle = loop_cycle(h + dh + 2 * s, spd, n)
            for i in range(count):
                x = (i * (w * 10 // count) // 10 + xoff) % w
                phase = i * cycle // count
                y = loop_pos(f, n, cycle, spd, phase)
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
        shimmer_cycle = loop_cycle(w, 2, n)
        shimmer_x = loop_pos(f, n, shimmer_cycle, 2, 0)
        parts.append(p(shimmer_x, h - 1 * s, 4 * s, 1 * s, "#4169E120"))

        bg = render.Box(width = w, height = h, color = "#000000")
        frames.append(render.Stack(children = [bg] + parts))
    return frames

def snow_frames(w, h, n, scale):
    """Layered snowfall with varying flake sizes, wobble, and ground buildup."""
    s = scale
    frames = []

    # (count, speed_mult, size, wobble_range, color)
    layers = [
        (6, 1, 1 * s, 1, "#FFFFFF25"),  # back: tiny, slow, dim
        (10, 2, 1 * s, 2, "#FFFFFF60"),  # mid: normal
        (6, 3, 2 * s, 3, "#FFFFFFA0"),  # front: large, fast, bright
    ]

    for f in range(n):
        parts = []

        # Ground snow buildup (static white bar)
        parts.append(p(0, h - 2 * s, w, 2 * s, "#FFFFFF18"))
        parts.append(p(2 * s, h - 3 * s, 5 * s, 1 * s, "#FFFFFF10"))
        parts.append(p(w - 8 * s, h - 3 * s, 6 * s, 1 * s, "#FFFFFF10"))

        for count, spd, sz, wob, color in layers:
            cycle = loop_cycle(h + sz, spd, n)
            wob_cycle = wob * 2 + 1
            for i in range(count):
                phase = i * cycle // count
                y = loop_pos(f, n, cycle, spd, phase)
                wob_phase = (i * 3) % wob_cycle
                wobble = loop_pos(f, n, wob_cycle, 2, wob_phase) - wob
                x = ((i * (w * 10 // count) // 10 + 2 * s) + wobble * s) % w
                if y <= h - sz - 2 * s:
                    parts.append(p(x, y, sz, sz, color))

        bg = render.Box(width = w, height = h, color = "#000000")
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

    # Two evenly-spaced lightning strikes per loop, derived from n
    s1 = n // 8  # first strike start
    s2 = s1 + n // 2  # second strike start
    flash_frames = [s1, s1 + 1, s1 + 2, s2, s2 + 1, s2 + 2]
    peak_frames = [s1 + 1, s2 + 1]
    glow_frames = [s1 + 3, s2 + 3]
    bolt2_frames = [s2, s2 + 1, s2 + 2]

    for f in range(n):
        layers = [base[f]]

        if f in flash_frames:
            bright = "90" if f in peak_frames else "50"
            layers.append(render.Box(width = w, height = h, color = "#FFFF00" + bright))

            bolt_color = "#FFFFFFD0" if f in peak_frames else "#FFFF8080"
            for dx, dy, bw, bh in bolt_segs:
                bx = bolt_x_base + dx
                if bx >= 0 and bx + bw <= w and dy + bh <= h:
                    layers.append(p(bx, dy, bw, bh, bolt_color))

            # Draw bolt 2 on second flash
            if f in bolt2_frames:
                for dx, dy, bw, bh in bolt2_segs:
                    bx = bolt2_x_base + dx
                    if bx >= 0 and bx + bw <= w and dy + bh <= h:
                        layers.append(p(bx, dy, bw, bh, bolt_color))

        elif f in glow_frames:
            layers.append(render.Box(width = w, height = h, color = "#FFFFFF15"))

        result.append(render.Stack(children = layers))
    return result

def sleet_frames(w, h, n, scale):
    """Dense mix of fast rain streaks and slower drifting snow."""
    s = scale
    frames = []

    rain_cycle = loop_cycle(h + 3 * s, 2, n)
    snow_cycle = loop_cycle(h + 2 * s, 1, n)

    for f in range(n):
        parts = []

        # Wet ground
        parts.append(p(0, h - 1 * s, w, 1 * s, "#4169E118"))

        # Rain drops (fast, angled feel via offset x)
        for i in range(10):
            x = (i * (w * 10 // 10) // 10 + (f % 3) * s) % w
            phase = i * rain_cycle // 10
            y = loop_pos(f, n, rain_cycle, 2, phase)
            if y <= h - 3 * s:
                parts.append(p(x, y, 1 * s, 3 * s, "#4169E180"))

        # Snow flakes (slow, wobble)
        for i in range(8):
            wob_phase = (i * 2) % 5
            wobble = loop_pos(f, n, 5, 2, wob_phase) - 2
            x = ((i * (w * 10 // 8) // 10 + 3 * s) + wobble * s) % w
            phase = i * snow_cycle // 8
            y = loop_pos(f, n, snow_cycle, 1, phase)
            sz = (2 * s) if i % 3 == 0 else (1 * s)
            if y <= h - sz - 1 * s:
                parts.append(p(x, y, sz, sz, "#FFFFFF70"))

        bg = render.Box(width = w, height = h, color = "#000000")
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
            abs_spd = max(1, abs(spd))
            cycle = loop_cycle(w + bw, abs_spd, n)
            fwd = loop_pos(f, n, cycle, abs_spd, 0)
            drift = fwd if spd > 0 else (cycle - fwd) % cycle
            x = drift - bw

            # Pulse alpha slightly
            pulse = ((f * 3 + y_base) % 8)
            a = alpha_base + (pulse if pulse < 4 else 8 - pulse) * 3
            ahex = hex02(min(a, 255))

            vis_x = max(0, x)
            vis_w = min(bw, w - vis_x)
            if vis_w > 0 and x + bw > 0:
                parts.append(
                    render.Padding(
                        pad = (vis_x, y_base, 0, 0),
                        child = render.Box(width = vis_w, height = bh, color = "#9999AA" + ahex),
                    ),
                )

        bg = render.Box(width = w, height = h, color = "#000000")
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
            abs_spd = max(1, abs(spd))
            cycle = loop_cycle(w + cw + 10 * s, abs_spd, n)
            offset = cw + 5 * s
            phase = (cy * 3) % cycle
            fwd = loop_pos(f, n, cycle, abs_spd, phase)
            drift = fwd if spd > 0 else (cycle - loop_pos(f, n, cycle, abs_spd, 0) + phase) % cycle
            x = drift - offset
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

        bg = render.Box(width = w, height = h, color = "#000000")
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
        parts = [render.Box(width = w, height = h, color = "#000000")]

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
            "#FFD700" + hex02(a // 3),
        ))

        # Mid glow
        mid_r = sun_r + 2 * s
        parts.append(p(
            max(0, sun_x - 2 * s),
            max(0, sun_y - 2 * s),
            min(mid_r * 2, w - max(0, sun_x - 2 * s)),
            mid_r * 2,
            "#FFD700" + hex02(a * 2 // 3),
        ))

        # Sun core
        parts.append(p(sun_x, sun_y, sun_r * 2, sun_r * 2, "#FFD700" + hex02(min(a + 30, 200))))

        # Rays extending from sun (4 diagonal directions)
        ray_len = (3 + (cycle % 4)) * s
        ray_color = "#FFD700" + hex02(a // 2)
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
    frame = render.Box(width = w, height = h, color = "#000000")
    return [frame] * n

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

HEX_CHARS = "0123456789abcdef"

def hex02(v):
    """Format an integer as a 2-digit lowercase hex string."""
    v = int(v)
    if v < 0:
        v = 0
    if v > 255:
        v = 255
    return HEX_CHARS[v // 16] + HEX_CHARS[v % 16]

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

    debug_options = [schema.Option(display = "None (use API)", value = "none")]
    for code in CONDITIONS_KEYS:
        label = CONDITIONS[code][0]
        debug_options.append(schema.Option(display = "%s (%s)" % (label, code), value = code))

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
            schema.Dropdown(
                id = "debug_anim",
                name = "Debug Animation",
                desc = "Override weather with a specific symbol for testing.",
                icon = "bug",
                default = "none",
                options = debug_options,
            ),
        ],
    )
