import os, math, random, datetime as dt
from flask import Flask, render_template, jsonify
import requests

app = Flask(__name__)

OWM_API_KEY = os.environ.get("OWM_API_KEY", "")
CITY = os.environ.get("CITY", "Boca Raton")
COUNTRY = os.environ.get("COUNTRY", "US")
UNITS = os.environ.get("UNITS", "imperial")  # "imperial" (°F), "metric" (°C)

QUOTES = [
    "Start where you are. Use what you have. Do what you can.",
    "What you do every day matters more than what you do once in a while.",
    "Stay focused. The storm will pass.",
    "Small steps add up.",
    "Discipline beats motivation.",
    "One thing at a time.",
]

def k_to_unit(k, units):
    if units == "metric":
        return k - 273.15
    if units == "imperial":
        return (k - 273.15) * 9/5 + 32
    return k

def fetch_weather():
    if not OWM_API_KEY:
        return {"error": "Missing OWM_API_KEY env var."}

    # Current weather
    cur_url = "https://api.openweathermap.org/data/2.5/weather"
    cur_params = {"q": f"{CITY},{COUNTRY}", "appid": OWM_API_KEY}
    cur = requests.get(cur_url, params=cur_params, timeout=10).json()
    if "main" not in cur:
        return {"error": cur.get("message", "Weather fetch failed.")}

    # 5-day / 3-hour forecast
    fc_url = "https://api.openweathermap.org/data/2.5/forecast"
    fc_params = {"q": f"{CITY},{COUNTRY}", "appid": OWM_API_KEY}
    fc = requests.get(fc_url, params=fc_params, timeout=10).json()
    if "list" not in fc:
        return {"error": fc.get("message", "Forecast fetch failed.")}

    units = UNITS
    cur_temp = k_to_unit(cur["main"]["temp"], units)
    feels = k_to_unit(cur["main"]["feels_like"], units)
    wind = cur.get("wind", {}).get("speed", 0)
    desc = cur["weather"][0]["description"].title()
    icon = cur["weather"][0]["icon"]  # e.g. "10d"

    # Next ~24 hours: take first 8 forecast slots (3h each)
    hourly = []
    for item in fc["list"][:8]:
        ts = dt.datetime.fromtimestamp(item["dt"])
        hourly.append({
            "time": ts.strftime("%a %I %p"),
            "temp": round(k_to_unit(item["main"]["temp"], units)),
            "icon": item["weather"][0]["icon"],
            "desc": item["weather"][0]["description"].title()
        })

    # Daily highs/lows for the next 3 days (simple aggregation by date)
    days = {}
    for item in fc["list"]:
        local = dt.datetime.fromtimestamp(item["dt"])
        day_key = local.strftime("%Y-%m-%d")
        t = k_to_unit(item["main"]["temp"], units)
        if day_key not in days:
            days[day_key] = {"hi": t, "lo": t, "icon": item["weather"][0]["icon"], "label": local.strftime("%a")}
        else:
            days[day_key]["hi"] = max(days[day_key]["hi"], t)
            days[day_key]["lo"] = min(days[day_key]["lo"], t)

    # Keep today + next 2
    daily = []
    for day_key in sorted(days.keys())[:3]:
        d = days[day_key]
        daily.append({
            "label": d["label"],
            "hi": round(d["hi"]),
            "lo": round(d["lo"]),
            "icon": d["icon"],
        })

    return {
        "location": f"{cur['name']}, {cur['sys'].get('country','')}",
        "units": units,
        "current": {
            "temp": round(cur_temp),
            "feels_like": round(feels),
            "wind": wind,
            "desc": desc,
            "icon": icon,
        },
        "hourly": hourly,
        "daily": daily,
    }

@app.route("/api/data")
def api_data():
    weather = fetch_weather()
    quote = random.choice(QUOTES)
    now = dt.datetime.now().strftime("%A, %B %d • %I:%M %p")
    return jsonify({"now": now, "quote": quote, "weather": weather})

@app.route("/")
def index():
    return render_template("index.html")

if __name__ == "__main__":
    # Dev server (gunicorn is used in container)
    app.run(host="0.0.0.0", port=5000)
