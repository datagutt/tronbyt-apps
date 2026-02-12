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
    dim = render.Box(width = w, height = h, color = "#00000055")
    children = []
    for frame in bg_frames:
        children.append(render.Stack(children = [frame, dim, overlay]))

    return render.Root(
        delay = FRAME_DELAY,
        child = render.Animation(children = children),
    )

# ---------------------------------------------------------------------------
# Weather type mapping
# ---------------------------------------------------------------------------

def get_weather_type(symbol_code):
    """Get simplified weather type for animation selection."""
    code = symbol_code
    for suffix in ["_day", "_night", "_polartwilight"]:
        code = code.replace(suffix, "")
    if "thunder" in code:
        return "thunder"
    if "snow" in code:
        return "snow"
    if "sleet" in code:
        return "sleet"
    if "rain" in code:
        return "rain"
    if code == "fog":
        return "fog"
    if code in ["cloudy", "partlycloudy"]:
        return "cloudy"
    if code in ["clearsky", "fair"]:
        return "clear"
    return "default"

def get_condition(symbol_code):
    """Map YR symbol code to display text and color."""
    code = symbol_code
    for suffix in ["_day", "_night", "_polartwilight"]:
        code = code.replace(suffix, "")
    if "thunder" in code:
        return ("Thunder", "#FF4500")
    if code == "clearsky":
        return ("Clear sky", "#FFD700")
    if code == "fair":
        return ("Fair", "#FFE4B5")
    if code == "partlycloudy":
        return ("Partly cloudy", "#B0B0B0")
    if code == "cloudy":
        return ("Cloudy", "#808080")
    if code == "fog":
        return ("Fog", "#696969")
    if "heavysnow" in code:
        return ("Heavy snow", "#E8E8FF")
    if "lightsnow" in code:
        return ("Light snow", "#F0F0F0")
    if "snow" in code:
        return ("Snow", "#E8E8E8")
    if "heavysleet" in code:
        return ("Heavy sleet", "#5F9EA0")
    if "sleet" in code:
        return ("Sleet", "#87CEEB")
    if "heavyrain" in code:
        return ("Heavy rain", "#1E3A8A")
    if "lightrain" in code:
        return ("Light rain", "#6495ED")
    if "rain" in code:
        return ("Rain", "#4169E1")
    if code:
        return (code, "#FFFFFF")
    return ("Unknown", "#FFFFFF")

# ---------------------------------------------------------------------------
# Animation frame generators
# ---------------------------------------------------------------------------

def make_weather_frames(weather_type, w, h, n, scale):
    """Dispatch to the right animation generator."""
    if weather_type == "rain":
        return rain_frames(w, h, n, scale)
    if weather_type == "thunder":
        return thunder_frames(w, h, n, scale)
    if weather_type == "snow":
        return snow_frames(w, h, n, scale)
    if weather_type == "sleet":
        return sleet_frames(w, h, n, scale)
    if weather_type == "fog":
        return fog_frames(w, h, n, scale)
    if weather_type == "cloudy":
        return cloud_frames(w, h, n, scale)
    if weather_type == "clear":
        return clear_frames(w, h, n, scale)
    return default_frames(w, h, n)

def particle(x, y, pw, ph, color):
    """Create a single positioned particle."""
    return render.Padding(
        pad = (x, y, 0, 0),
        child = render.Box(width = pw, height = ph, color = color),
    )

def rain_frames(w, h, n, scale):
    """Falling blue rain streaks."""
    count = 14
    speed = 2 * scale
    dw = 1 * scale
    dh = 2 * scale
    frames = []
    for f in range(n):
        parts = []
        for i in range(count):
            x = (i * (w * 10 // count) // 10 + 1 * scale) % w
            y = (f * speed + i * (h * 10 // 4) // 10) % (h + dh)
            if y <= h - dh:
                parts.append(particle(x, y, dw, dh, "#4169E150"))
        bg = render.Box(width = w, height = h, color = "#06060e")
        frames.append(render.Stack(children = [bg] + parts) if parts else bg)
    return frames

def snow_frames(w, h, n, scale):
    """Drifting white snowflakes with gentle wobble."""
    count = 12
    sz = 1 * scale
    frames = []
    for f in range(n):
        parts = []
        for i in range(count):
            wobble = ((f + i * 3) % 5) - 2
            x = ((i * (w * 10 // count) // 10 + 2 * scale) + wobble * scale) % w
            y = (f * scale + i * (h * 10 // 4) // 10) % (h + sz)
            if y <= h - sz:
                parts.append(particle(x, y, sz, sz, "#FFFFFF45"))
        bg = render.Box(width = w, height = h, color = "#080812")
        frames.append(render.Stack(children = [bg] + parts) if parts else bg)
    return frames

def thunder_frames(w, h, n, scale):
    """Rain with intermittent lightning flashes."""
    base = rain_frames(w, h, n, scale)
    result = []
    for f in range(n):
        if f == 4 or f == 16:
            flash = render.Box(width = w, height = h, color = "#FFFF0050")
            result.append(render.Stack(children = [base[f], flash]))
        elif f == 5 or f == 17:
            flash = render.Box(width = w, height = h, color = "#FFFFFF25")
            result.append(render.Stack(children = [base[f], flash]))
        else:
            result.append(base[f])
    return result

def sleet_frames(w, h, n, scale):
    """Mixed rain drops and snow flakes."""
    dw = 1 * scale
    dh = 2 * scale
    sz = 1 * scale
    frames = []
    for f in range(n):
        parts = []

        # Rain drops
        for i in range(8):
            x = (i * (w * 10 // 8) // 10) % w
            y = (f * 2 * scale + i * (h * 10 // 3) // 10) % (h + dh)
            if y <= h - dh:
                parts.append(particle(x, y, dw, dh, "#4169E140"))

        # Snow flakes
        for i in range(6):
            wobble = ((f + i * 2) % 3) - 1
            x = ((i * (w * 10 // 6) // 10 + 3 * scale) + wobble * scale) % w
            y = (f * scale + i * (h * 10 // 3) // 10) % (h + sz)
            if y <= h - sz:
                parts.append(particle(x, y, sz, sz, "#FFFFFF40"))

        bg = render.Box(width = w, height = h, color = "#070710")
        frames.append(render.Stack(children = [bg] + parts) if parts else bg)
    return frames

def fog_frames(w, h, n, scale):
    """Slowly drifting horizontal fog bands."""
    bh = 2 * scale
    frames = []
    for f in range(n):
        parts = []
        for i in range(5):
            y = (i * (h // 5) + 1 * scale) % h
            drift = (f // 3 + i * 2) % 4 - 2
            bw = w * 2 // 3 + (i * 7 % (w // 4))
            x = (drift * scale + i * (w // 5)) % (w + bw // 2) - bw // 4
            parts.append(
                render.Padding(
                    pad = (max(0, x), y, 0, 0),
                    child = render.Box(
                        width = min(bw, w - max(0, x)),
                        height = bh,
                        color = "#88888818",
                    ),
                ),
            )
        bg = render.Box(width = w, height = h, color = "#0a0a0e")
        frames.append(render.Stack(children = [bg] + parts))
    return frames

def cloud_frames(w, h, n, scale):
    """Slowly drifting cloud rectangles."""
    frames = []
    cw = 12 * scale
    ch = 4 * scale
    for f in range(n):
        parts = []
        for i in range(3):
            speed = 1 + (i % 2)
            x = ((f * speed + i * 20 * scale) // 2) % (w + cw) - cw
            y = (2 + i * 5) * scale
            cur_w = cw + (i * 3) * scale
            alpha = "1c" if i % 2 == 0 else "14"
            vis_x = max(0, x)
            vis_w = min(cur_w, w - vis_x)
            if vis_w > 0 and x + cur_w > 0:
                parts.append(
                    render.Padding(
                        pad = (vis_x, y, 0, 0),
                        child = render.Box(width = vis_w, height = ch, color = "#888888" + alpha),
                    ),
                )
        bg = render.Box(width = w, height = h, color = "#08080e")
        frames.append(render.Stack(children = [bg] + parts) if parts else bg)
    return frames

def clear_frames(w, h, n, scale):
    """Pulsing warm sun glow in the corner."""
    sun = 6 * scale
    glow = sun + 2 * scale
    frames = []
    for f in range(n):
        cycle = f % 12
        if cycle < 6:
            a = 15 + cycle * 5
        else:
            a = 45 - (cycle - 6) * 5
        glow_hex = "#FFD700" + "%02x" % a
        sun_hex = "#FFD700" + "%02x" % min(a + 20, 80)
        parts = [
            render.Box(width = w, height = h, color = "#0a0a08"),
            render.Padding(
                pad = (w - glow - scale, scale, 0, 0),
                child = render.Box(width = glow, height = glow, color = glow_hex),
            ),
            render.Padding(
                pad = (w - sun - 2 * scale, 2 * scale, 0, 0),
                child = render.Box(width = sun, height = sun, color = sun_hex),
            ),
        ]
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
