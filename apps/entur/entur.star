"""
Applet: Entur
Summary: Norway transit departures
Description: Real-time public transit departures for any stop in Norway using the Entur API. Shows line numbers, destinations, and countdown times with transport mode color coding.
Author: datagutt
"""

load("encoding/json.star", "json")
load("http.star", "http")
load("render.star", "canvas", "render")
load("schema.star", "schema")
load("time.star", "time")

ENTUR_API_URL = "https://api.entur.io/journey-planner/v3/graphql"
GEOCODER_URL = "https://api.entur.io/geocoder/v1/autocomplete"
CLIENT_NAME = "tronbyt-entur"
DEPARTURES_TTL = 60
GEOCODER_TTL = 300

DEFAULT_STOP_ID = "NSR:StopPlace:58366"
DEFAULT_STOP_NAME = "Jernbanetorget"
DEFAULT_SEARCH = '{"display": "Jernbanetorget", "value": "NSR:StopPlace:58366"}'

MODE_COLORS = {
    "bus": "#E60000",
    "tram": "#0B91EF",
    "metro": "#F68712",
    "rail": "#7B3F98",
    "water": "#2BA5B5",
    "coach": "#008545",
}

HEADER_BG = "#222222"
SEP_COLOR = "#333333"
WHITE = "#FFFFFF"
YELLOW = "#F9C66B"
GREY = "#AAAAAA"

GRAPHQL_QUERY = """
query ($id: String!, $timeRange: Int!, $n: Int!) {
  stopPlace(id: $id) {
    name
    estimatedCalls(timeRange: $timeRange, numberOfDepartures: $n) {
      expectedDepartureTime
      aimedDepartureTime
      cancellation
      destinationDisplay {
        frontText
      }
      serviceJourney {
        line {
          publicCode
          transportMode
          presentation {
            colour
          }
        }
        journeyPattern {
          directionType
        }
      }
    }
  }
}
"""

def main(config):
    search_raw = config.get("stop", DEFAULT_SEARCH)
    search = json.decode(search_raw)
    stop_id = search.get("value", DEFAULT_STOP_ID)
    stop_name = search.get("display", DEFAULT_STOP_NAME)

    direction = config.get("direction", "all")
    max_deps = int(config.get("max_departures", "10"))

    # Transport mode filters - default to showing all
    allowed_modes = []
    for mode in ["bus", "tram", "metro", "rail", "water", "coach"]:
        if config.get("show_" + mode) != "false":
            allowed_modes.append(mode)

    # Canvas setup
    scale = 2 if canvas.is2x() else 1
    w = canvas.width()
    h = canvas.height()
    font = "tom-thumb" if scale == 1 else "terminus-12"

    # Layout dimensions
    header_h = 7 * scale
    sep_h = 1 * scale
    row_h = 8 if scale == 1 else 12
    rows_visible = 3 if scale == 1 else 4

    # Column widths
    code_w = 13 * scale
    time_w = 25 if scale == 1 else 46
    dest_w = w - code_w - time_w

    # Fetch departures
    headers = {
        "ET-Client-Name": CLIENT_NAME,
        "Content-Type": "application/json",
    }

    rep = http.post(
        ENTUR_API_URL,
        json_body = {
            "query": GRAPHQL_QUERY,
            "variables": {
                "id": stop_id,
                "timeRange": 3600,
                "n": max_deps,
            },
        },
        headers = headers,
        ttl_seconds = DEPARTURES_TTL,
    )

    if rep.status_code != 200:
        return render_error("API error: %d" % rep.status_code, w, h, font)

    data = rep.json()
    stop_place = data.get("data", {}).get("stopPlace", {})
    if not stop_place:
        return render_error("Stop not found", w, h, font)

    calls = stop_place.get("estimatedCalls", [])
    actual_name = stop_place.get("name", stop_name)

    # Filter and process departures
    now = time.now().in_location("Europe/Oslo")
    departures = []

    for call in calls:
        if call.get("cancellation", False):
            continue

        sj = call.get("serviceJourney", {})
        line = sj.get("line", {})
        mode = line.get("transportMode", "")

        if mode and mode not in allowed_modes:
            continue

        if direction != "all":
            dir_type = sj.get("journeyPattern", {}).get("directionType", "")
            if dir_type != direction:
                continue

        dep_str = call.get("expectedDepartureTime", call.get("aimedDepartureTime", ""))
        if not dep_str:
            continue

        dep_time = time.parse_time(dep_str, location = "Europe/Oslo")
        diff = (dep_time - now).seconds

        # Skip past departures
        if diff < -30:
            continue

        # Format as 24h clock time
        dep_local = dep_time.in_location("Europe/Oslo")
        time_text = dep_local.format("15:04")

        # Line color from API or fallback to mode color
        colour = line.get("presentation", {}).get("colour", "")
        if colour and colour != "000000":
            line_color = "#" + colour if not colour.startswith("#") else colour
        else:
            line_color = MODE_COLORS.get(mode, WHITE)

        departures.append({
            "code": line.get("publicCode", ""),
            "dest": call.get("destinationDisplay", {}).get("frontText", ""),
            "time": time_text,
            "color": line_color,
        })

        if len(departures) >= rows_visible:
            break

    if not departures:
        return render.Root(
            max_age = 60,
            child = render.Column(
                children = [
                    render_header(actual_name, w, header_h, font, scale),
                    render.Box(width = w, height = sep_h, color = SEP_COLOR),
                    render.Box(
                        width = w,
                        height = h - header_h - sep_h,
                        child = render.WrappedText(
                            content = "Ingen avganger",
                            font = font,
                            color = GREY,
                        ),
                    ),
                ],
            ),
        )

    # Build departure rows
    rows = []
    for dep in departures:
        rows.append(
            render.Box(
                width = w,
                height = row_h,
                child = render.Row(
                    cross_align = "center",
                    children = [
                        render.Box(
                            width = code_w,
                            height = row_h,
                            child = render.Padding(
                                pad = (1 * scale, 0, 0, 0),
                                child = render.Text(
                                    content = dep["code"],
                                    font = font,
                                    color = dep["color"],
                                ),
                            ),
                        ),
                        render.Marquee(
                            width = dest_w,
                            child = render.Text(
                                content = dep["dest"],
                                font = font,
                                color = WHITE,
                            ),
                        ),
                        render.Box(
                            width = time_w,
                            height = row_h,
                            child = render.Text(
                                content = dep["time"],
                                font = font,
                                color = YELLOW,
                            ),
                        ),
                    ],
                ),
            ),
        )

    return render.Root(
        max_age = 60,
        child = render.Column(
            children = [
                render_header(actual_name, w, header_h, font, scale),
                render.Box(width = w, height = sep_h, color = SEP_COLOR),
            ] + rows,
        ),
    )

def render_header(name, w, header_h, font, scale):
    return render.Box(
        width = w,
        height = header_h,
        color = HEADER_BG,
        child = render.Padding(
            pad = (1 * scale, 0, 0, 0),
            child = render.Marquee(
                width = w - 2 * scale,
                child = render.Text(
                    content = name,
                    font = font,
                    color = GREY,
                ),
            ),
        ),
    )

def render_error(msg, w, h, font):
    return render.Root(
        child = render.Box(
            width = w,
            height = h,
            child = render.WrappedText(
                content = msg,
                font = font,
                color = "#FF0000",
            ),
        ),
    )

def search_stops(pattern):
    headers = {
        "ET-Client-Name": CLIENT_NAME,
    }
    rep = http.get(
        GEOCODER_URL + "?text=" + pattern + "&size=10&lang=no&layers=venue",
        headers = headers,
        ttl_seconds = GEOCODER_TTL,
    )
    if rep.status_code != 200:
        return []

    data = rep.json()
    options = []
    for feature in data.get("features", []):
        props = feature.get("properties", {})
        fid = props.get("id", "")
        if fid.startswith("NSR:StopPlace"):
            label = props.get("label", props.get("name", ""))
            options.append(
                schema.Option(
                    display = label,
                    value = fid,
                ),
            )
    return options

def get_schema():
    direction_options = [
        schema.Option(display = "All", value = "all"),
        schema.Option(display = "Outbound", value = "outbound"),
        schema.Option(display = "Inbound", value = "inbound"),
    ]

    max_dep_options = [
        schema.Option(display = "5", value = "5"),
        schema.Option(display = "10", value = "10"),
        schema.Option(display = "15", value = "15"),
        schema.Option(display = "20", value = "20"),
    ]

    return schema.Schema(
        version = "1",
        fields = [
            schema.Typeahead(
                id = "stop",
                name = "Stop",
                desc = "Search for a stop in Norway",
                icon = "trainSubway",
                handler = search_stops,
            ),
            schema.Dropdown(
                id = "direction",
                name = "Direction",
                desc = "Filter by travel direction",
                icon = "compass",
                default = "all",
                options = direction_options,
            ),
            schema.Dropdown(
                id = "max_departures",
                name = "Max departures",
                desc = "Maximum number of departures to fetch",
                icon = "list",
                default = "10",
                options = max_dep_options,
            ),
            schema.Toggle(
                id = "show_bus",
                name = "Bus",
                desc = "Show bus departures",
                icon = "bus",
                default = True,
            ),
            schema.Toggle(
                id = "show_tram",
                name = "Tram",
                desc = "Show tram departures",
                icon = "trainTram",
                default = True,
            ),
            schema.Toggle(
                id = "show_metro",
                name = "Metro",
                desc = "Show metro departures",
                icon = "trainSubway",
                default = True,
            ),
            schema.Toggle(
                id = "show_rail",
                name = "Rail",
                desc = "Show rail departures",
                icon = "train",
                default = True,
            ),
            schema.Toggle(
                id = "show_water",
                name = "Ferry",
                desc = "Show ferry departures",
                icon = "ship",
                default = True,
            ),
            schema.Toggle(
                id = "show_coach",
                name = "Coach",
                desc = "Show coach departures",
                icon = "bus",
                default = True,
            ),
        ],
    )
