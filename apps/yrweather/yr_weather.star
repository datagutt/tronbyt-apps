"""
Applet: YR Weather
Summary: Weather from YR/MET.no
Description: Display weather from the Norwegian Meteorological Institute. Supports Locationforecast (global) and Nowcast (Nordic area).
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

    # Current conditions from first entry
    current = series[0]
    instant = current.get("data", {}).get("instant", {}).get("details", {})

    temp_c = instant.get("air_temperature", 0)
    wind = instant.get("wind_speed", 0)

    # Symbol and precipitation from next_1_hours, fallback to next_6_hours
    next_h = current.get("data", {}).get("next_1_hours")
    if not next_h:
        next_h = current.get("data", {}).get("next_6_hours", {})

    symbol = ""
    precip = 0.0
    if next_h:
        symbol = next_h.get("summary", {}).get("symbol_code", "")
        precip = next_h.get("details", {}).get("precipitation_amount", 0.0)

    # Format temperature
    if units == "fahrenheit":
        temp_val = temp_c * 9.0 / 5.0 + 32.0
        temp_str = "%d°F" % int(temp_val)
    else:
        temp_str = "%d°C" % int(temp_c)

    condition_text, condition_color = get_condition(symbol)
    source_label = "Nowcast" if source == "nowcast" else "Forecast"

    scale = 2 if canvas.is2x() else 1
    sm_font = "tom-thumb" if scale == 1 else "terminus-12"
    lg_font = "6x13" if scale == 1 else "terminus-16"
    box_size = 4 * scale
    spacer = 2 * scale

    return render.Root(
        child = render.Column(
            expanded = True,
            main_align = "space_between",
            children = [
                # Location + source
                render.Row(
                    expanded = True,
                    main_align = "space_between",
                    children = [
                        render.Text(
                            content = locality if locality else source_label,
                            font = sm_font,
                            color = "#888888",
                        ),
                        render.Text(
                            content = source_label if locality else "",
                            font = sm_font,
                            color = "#666666",
                        ),
                    ],
                ),
                # Temperature + condition indicator
                render.Row(
                    cross_align = "center",
                    children = [
                        render.Box(width = box_size, height = box_size, color = condition_color),
                        render.Box(width = spacer, height = 1),
                        render.Text(content = temp_str, font = lg_font, color = "#FFFFFF"),
                    ],
                ),
                # Condition text
                render.Text(
                    content = condition_text,
                    font = sm_font,
                    color = condition_color,
                ),
                # Wind + precipitation
                render.Row(
                    expanded = True,
                    main_align = "space_between",
                    children = [
                        render.Text(
                            content = fmt1(wind) + " m/s",
                            font = sm_font,
                            color = "#AAAAAA",
                        ),
                        render.Text(
                            content = fmt1(precip) + " mm",
                            font = sm_font,
                            color = "#4169E1",
                        ),
                    ],
                ),
            ],
        ),
    )

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
