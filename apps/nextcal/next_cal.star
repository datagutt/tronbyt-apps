load("encoding/json.star", "json")
load("http.star", "http")
load("humanize.star", "humanize")
load("images/calendar_icon.png", CALENDAR_ICON_ASSET = "file")
load("images/heart.png", HEART_ASSET = "file")
load("render.star", "canvas", "render")
load("schema.star", "schema")
load("time.star", "time")

CALENDAR_ICON = CALENDAR_ICON_ASSET.readall()
HEART_ICON = HEART_ASSET.readall()

def main(config):
    scale = 2 if canvas.is2x() else 1
    w = canvas.width()

    location = config.str(P_LOCATION)
    location = json.decode(location) if location else {}
    timezone = location.get(
        "timezone",
        time.tz(),
    )

    show_expanded_time_window = config.bool("show_expanded_time_window", DEFAULT_SHOW_EXPANDED_TIME_WINDOW)
    show_full_names = config.bool("show_full_names", DEFAULT_SHOW_FULL_NAMES)

    ics_url = config.str("ics_url", DEFAULT_ICS_URL)
    show_in_progress = config.bool("show_in_progress", DEFAULT_SHOW_IN_PROGRESS)

    # get all day variable, set default to "showAllDay"
    all_day_behavior = config.get("all_day", "showAllDay")
    if (all_day_behavior == "onlyShowAllDay"):
        only_show_all_day = True
        include_all_day = True
    elif (all_day_behavior == "noShowAllDay"):
        include_all_day = False
        only_show_all_day = False
    else:
        # default behavior is to show all day
        include_all_day = True
        only_show_all_day = False

    if (ics_url == None):
        fail("ICS_URL not set in config")

    now = time.now().in_location(timezone)
    ics = http.post(
        url = LAMBDA_URL,
        json_body = {"icsUrl": ics_url, "tz": timezone, "showInProgress": show_in_progress, "includeAllDayEvents": include_all_day, "onlyShowAllDayEvents": only_show_all_day},
    )

    if (ics.status_code != 200):
        font = "tom-thumb" if scale == 1 else "terminus-12"
        return render.Root(child = render.WrappedText("Failed to fetch ICS file", color = "#ff0000", font = font))

    event = ics.json()["data"]

    if not event:
        return build_calendar_frame(now, timezone, event, show_expanded_time_window, show_full_names, scale, w)
        #if there's an event inProgress, and it's not an All Day event, show the event

    elif event["detail"]["inProgress"] and not event["detail"]["isAllDay"]:
        return build_event_frame(event, scale)
    elif event["detail"]:
        return build_calendar_frame(now, timezone, event, show_expanded_time_window, show_full_names, scale, w)
    else:
        return build_calendar_frame(now, timezone, event, show_expanded_time_window, show_full_names, scale, w)

def get_calendar_text_color(event):
    DEFAULT = "#ff83f3"
    if event["detail"]["isAllDay"]:
        return DEFAULT
    elif event["detail"]["minutesUntilStart"] <= 5:
        return "#ff5000"
    elif event["detail"]["minutesUntilStart"] <= 2:
        return "#9000ff"
    else:
        return DEFAULT

def should_animate_text(event):
    if event["detail"]["isAllDay"]:
        return False
    return event["detail"]["minutesUntilStart"] <= 5

def get_tomorrow_text_copy(eventStart, show_full_names):
    DEFAULT = eventStart.format("TMRW 3:04 PM")
    if show_full_names:
        return eventStart.format("Tomorrow at 3:04 PM")
    else:
        return DEFAULT

def get_this_week_text_copy(eventStart, show_full_names):
    DEFAULT = eventStart.format("Mon at 3:04 PM")

    if show_full_names:
        return eventStart.format("Monday at 3:04 PM")
    else:
        return DEFAULT

def get_expanded_time_text_copy(event, now, eventStart, eventEnd, show_full_names):
    DEFAULT = "in %s" % humanize.relative_time(now, eventStart)

    multiday = False

    # check if it's a multi-day event
    if event["detail"]["isAllDay"] and eventStart.day != eventEnd.day:
        multiday = True

    if event["detail"]["isAllDay"]:
        # if it's in progress, show the day it ends
        if event["detail"]["inProgress"] and multiday:
            return eventEnd.format("until Mon")  # + " " + humanize.ordinal(eventEnd.day)
            # if the event is all day and ends today, show nothing

        elif event["detail"]["inProgress"]:
            return eventEnd.format("")
            # if the event is all day but not started, just show the day it starts

        else:
            return eventStart.format("on Mon")
    elif event["detail"]["isTomorrow"]:
        return get_tomorrow_text_copy(eventStart, show_full_names)

    elif event["detail"]["isThisWeek"]:
        return get_this_week_text_copy(eventStart, show_full_names)
    else:
        return DEFAULT

def get_calendar_text_copy(event, now, eventStart, eventEnd, show_expanded_time_window, show_full_names):
    DEFAULT = eventStart.format("at 3:04 PM")

    if not event["detail"]["isToday"] and not show_expanded_time_window:
        return DONE_TEXT
    elif event["detail"]["isToday"] and not event["detail"]["inProgress"]:
        return DEFAULT
    elif event["detail"] and show_expanded_time_window:
        return get_expanded_time_text_copy(event, now, eventStart, eventEnd, show_full_names)
    elif event["detail"] and not event["detail"]["isAllDay"] and event["detail"]["minutesUntilStart"] <= 5:
        return "in %d min" % event["detail"]["minutesUntilStart"]
    elif event["detail"]["isAllDay"] and not show_expanded_time_window:
        return get_expanded_time_text_copy(event, now, eventStart, eventEnd, show_full_names)
    else:
        return DEFAULT

def get_calendar_render_data(now, usersTz, event, show_expanded_time_window, show_full_names):
    baseObject = {
        "currentMonth": now.format("Jan").upper(),
        "currentDay": humanize.ordinal(now.day),
        "now": now,
    }

    #if there's no event or it is an all day event, build the top part of calendar as usual
    if not event:
        baseObject["hasEvent"] = False
        return baseObject

    shouldRenderSummary = event["detail"]["isToday"] or show_expanded_time_window
    if not shouldRenderSummary:
        baseObject["hasEvent"] = False
        return baseObject

    startTime = time.from_timestamp(int(event["start"])).in_location(usersTz)
    endTime = time.from_timestamp(int(event["end"])).in_location(usersTz)
    eventObject = {
        "summary": get_event_summary(event["name"]),
        "eventStartTimestamp": startTime,
        "copy": get_calendar_text_copy(event, now, startTime, endTime, show_expanded_time_window, show_full_names),
        "textColor": get_calendar_text_color(event),
        "shouldAnimateText": should_animate_text(event),
        "hasEvent": True,
        "isToday": event["detail"]["isToday"],
        "isAllDay": event["detail"]["isAllDay"],
    }

    return dict(baseObject.items() + eventObject.items())

def render_calendar_base_object(top, bottom, scale):
    return render.Root(
        delay = FRAME_DELAY,
        child = render.Box(
            padding = 2 * scale,
            color = "#000",
            child = render.Column(
                expanded = True,
                children = top + bottom,
            ),
        ),
    )

def get_calendar_top(data, scale):
    font = "tom-thumb" if scale == 1 else "terminus-12"
    return [
        render.Row(
            cross_align = "center",
            expanded = True,
            children = [
                render.Image(src = CALENDAR_ICON, width = 9 * scale, height = 11 * scale),
                render.Box(width = 2 * scale, height = 1 * scale),
                render.Text(
                    data["currentMonth"],
                    color = "#ff83f3",
                    font = font,
                    offset = -1 * scale,
                ),
                render.Box(width = 1 * scale, height = 1 * scale),
                render.Text(
                    data["currentDay"],
                    color = "#ff83f3",
                    font = font,
                    offset = -1 * scale,
                ),
            ],
        ),
        render.Box(height = 2 * scale),
    ]

def get_calendar_bottom(data, scale, w):
    font = "tom-thumb" if scale == 1 else "terminus-12"
    children = []
    if data["hasEvent"]:
        children.append(
            render.Marquee(
                width = w,
                child = render.Text(
                    data["summary"],
                    font = font,
                ),
            ),
        )
        children.append(
            render.Marquee(
                width = w,
                child = render.Text(
                    data["copy"],
                    color = data["textColor"],
                    font = font,
                ),
            ),
        )

    if not data["hasEvent"]:
        children.append(
            render.Row(
                cross_align = "center",
                children = [
                    render.WrappedText(
                        DONE_TEXT,
                        color = "#ff83f3",
                        font = font,
                    ),
                    render.Box(width = 1 * scale, height = 1),
                    render.Image(src = HEART_ICON, width = 5 * scale, height = 5 * scale),
                ],
            ),
        )

    elif data["shouldAnimateText"]:
        children = [
            render.Animation(
                children,
            ),
        ]

    return [
        render.Column(
            expanded = True,
            main_align = "end",
            children = children,
        ),
    ]

def build_calendar_frame(now, usersTz, event, show_expanded_time_window, show_full_names, scale, w):
    data = get_calendar_render_data(now, usersTz, event, show_expanded_time_window, show_full_names)

    top = get_calendar_top(data, scale)
    bottom = get_calendar_bottom(data, scale, w)

    return render_calendar_base_object(
        top = top,
        bottom = bottom,
        scale = scale,
    )

def get_event_frame_copy_config(event):
    minutes_to_start = event["detail"]["minutesUntilStart"]
    minutes_to_end = event["detail"]["minutesUntilEnd"]
    hours_to_end = event["detail"]["hoursToEnd"]

    tagline = None
    if minutes_to_start >= 1:
        tagline = ("in %d" % minutes_to_start, "min")
    elif hours_to_end >= 99:
        tagline = ("", "now")
    elif minutes_to_end >= 99:
        tagline = ("Ends in %d" % hours_to_end, "h")
    elif minutes_to_end > 1:
        tagline = ("Ends in %d" % minutes_to_end, "min")
    else:
        tagline = ("", "almost done")

    return {
        "summary": get_event_summary(event["name"]),
        "tagline": tagline,
        "bgColor": "#ff78e9",
        "textColor": "#fff500",
    }

def build_event_frame(event, scale):
    font = "tom-thumb" if scale == 1 else "terminus-12"
    data = get_event_frame_copy_config(event)
    baseChildren = [
        render.WrappedText(
            data["summary"].upper(),
            height = 17 * scale,
            font = font,
        ),
        render.Box(
            color = data["bgColor"],
            height = 1 * scale,
        ),
        render.Box(height = 3 * scale),
        render.Row(
            main_align = "end",
            expanded = True,
            children = [
                render.Text(
                    data["tagline"][0],
                    color = data["textColor"],
                    font = font,
                ),
                render.Box(height = 1 * scale, width = 1 * scale),
                render.Text(
                    data["tagline"][1],
                    color = data["textColor"],
                    font = font,
                ),
            ],
        ),
    ]
    return render.Root(
        child = render.Box(
            padding = 2 * scale,
            child = render.Column(
                main_align = "start",
                cross_align = "start",
                expanded = True,
                children = baseChildren,
            ),
        ),
    )

def get_event_summary(summary):
    if DEFAULT_TRUNCATE_EVENT_SUMMARY:
        splitSum = summary.split()
        return " ".join(splitSum) if len(splitSum) <= 3 else " ".join(splitSum[:3]) + "..."
    else:
        return summary

def get_schema():
    options = [
        schema.Option(
            display = "Show All Day Events",
            value = "showAllDay",
        ),
        schema.Option(
            display = "Only Show All Day Events",
            value = "onlyShowAllDay",
        ),
        schema.Option(
            display = "Don't Show All Day Events",
            value = "noShowAllDay",
        ),
    ]

    return schema.Schema(
        version = "1",
        fields = [
            schema.Location(
                id = P_LOCATION,
                name = "Location",
                desc = "Location for the display of date and time.",
                icon = "locationDot",
            ),
            schema.Text(
                id = P_ICS_URL,
                name = "iCalendar URL",
                desc = "The URL of the iCalendar file.",
                icon = "calendar",
                default = DEFAULT_ICS_URL,
            ),
            schema.Toggle(
                id = P_SHOW_EXPANDED_TIME_WINDOW,
                name = "Show Expanded Time Window",
                desc = "Show events outside of a 24 hour window.",
                default = DEFAULT_SHOW_EXPANDED_TIME_WINDOW,
                icon = "clock",
            ),
            schema.Toggle(
                id = P_SHOW_FULL_NAMES,
                name = "Show Full Names",
                desc = "Show the full names of the days of the week.",
                default = DEFAULT_SHOW_FULL_NAMES,
                icon = "calendar",
            ),
            schema.Toggle(
                id = P_SHOW_IN_PROGRESS,
                name = "Show Events In Progress",
                desc = "Show events that are currently happening.",
                default = DEFAULT_SHOW_IN_PROGRESS,
                icon = "calendar",
            ),
            schema.Dropdown(
                id = P_ALL_DAY,
                name = "Show All Day Events",
                desc = "Turn on or off display of all day events.",
                default = options[0].value,
                options = options,
                icon = "calendar",
            ),
        ],
    )

P_LOCATION = "location"
P_ICS_URL = "ics_url"
P_SHOW_EXPANDED_TIME_WINDOW = "show_expanded_time_window"
P_SHOW_FULL_NAMES = "show_full_names"
P_SHOW_IN_PROGRESS = "show_in_progress"
P_TRUNCATE_EVENT_SUMMARY = "truncate_event_summary"
P_ALL_DAY = "all_day"

DONE_TEXT = "DONE FOR THE DAY"
DEFAULT_SHOW_EXPANDED_TIME_WINDOW = True
DEFAULT_TRUNCATE_EVENT_SUMMARY = True
DEFAULT_SHOW_FULL_NAMES = False
DEFAULT_SHOW_IN_PROGRESS = True
FRAME_DELAY = 50

LAMBDA_URL = "https://ics-calendar-tidbyt-vercel.vercel.app/api/ics-next-event"

#LAMBDA_URL = "https://6bfnhr9vy7.execute-api.us-east-1.amazonaws.com/ics-next-event"

#this is the original AWS Lambda URL that is hosting the helper function
#LAMBDA_URL = "https://xmd10xd284.execute-api.us-east-1.amazonaws.com/ics-next-event"

#this is a weird calendar but its the only public ics that reliably has events every week
DEFAULT_ICS_URL = "https://calendar.google.com/calendar/ical/ht3jlfaac5lfd6263ulfh4tql8%40group.calendar.google.com/public/basic.ics"
