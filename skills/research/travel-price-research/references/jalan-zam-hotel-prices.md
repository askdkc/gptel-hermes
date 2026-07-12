# Jalan ZAM hotel price summaries

Use this when researching Japanese hotel prices on Jalan (`jalan.net`) and the public hotel page exposes `window.ZAM`.

## Discovery

1. Fetch the hotel page with a browser-like user agent and decode as CP932/Shift_JIS if Japanese text is garbled.
2. Extract:
   - `window.ZAM.endpoint` (observed shape: `https://jlnzam.net/v2/search`)
   - `window.ZAM.apiKey` from `apiKey: '<value>'`
   - hotel ID from the URL, e.g. `https://www.jalan.net/yad324255/` → `324255`
3. Verify the page text contains the target hotel name.

## Request shape

POST JSON to the endpoint with headers:

```http
Content-Type: application/json
X-API-KEY: <apiKey>
Origin: https://www.jalan.net
Referer: https://www.jalan.net/yad<hotelId>/
User-Agent: Mozilla/5.0
```

Typical body for 1 night / 1 room / 2 adults:

```json
{
  "targets": ["324255"],
  "targetType": "HOTEL_ID",
  "nights": 1,
  "rooms": [
    {"adults": 2, "children1": 0, "children2": 0, "children3": 0, "children4": 0, "children5": 0}
  ],
  "hotelTypes": [],
  "extras": [],
  "checkInDateSearchFrom": "2026-07-09",
  "checkInDateSearchTo": "2026-07-31"
}
```

The API may reject overly long ranges with HTTP 400; query month-sized chunks.

## Response fields

The useful data is usually:

```python
hotel = data["data"]["hotels"][0]
hotel["hotelId"]
hotel["hotelName"]
hotel["summary"]  # list of date summaries
```

Each `summary` item can include:

```json
{
  "checkInDate": "2026-07-21",
  "lowestTotalPrice": 21510,
  "totalStock": 81
}
```

Rank only rows where `lowestTotalPrice` is present and `totalStock > 0`.

## Minimal Python pattern

```python
import json, re, urllib.request

hotel_id = "324255"
page = urllib.request.urlopen(
    urllib.request.Request(f"https://www.jalan.net/yad{hotel_id}/", headers={"User-Agent": "Mozilla/5.0"}),
    timeout=30,
).read().decode("cp932", "replace")
endpoint = re.search(r"endpoint:\\s*'([^']+)'", page).group(1)
api_key = re.search(r"apiKey:\\s*'([^']+)'", page).group(1)

body = {
    "targets": [hotel_id],
    "targetType": "HOTEL_ID",
    "nights": 1,
    "rooms": [{"adults": 2, "children1": 0, "children2": 0, "children3": 0, "children4": 0, "children5": 0}],
    "hotelTypes": [],
    "extras": [],
    "checkInDateSearchFrom": "2026-07-01",
    "checkInDateSearchTo": "2026-07-31",
}
req = urllib.request.Request(
    endpoint,
    data=json.dumps(body).encode(),
    headers={
        "User-Agent": "Mozilla/5.0",
        "Content-Type": "application/json",
        "X-API-KEY": api_key,
        "Origin": "https://www.jalan.net",
        "Referer": f"https://www.jalan.net/yad{hotel_id}/",
    },
)
data = json.loads(urllib.request.urlopen(req, timeout=60).read())
rows = [
    (s["checkInDate"], s.get("lowestTotalPrice"), s.get("totalStock"))
    for s in data["data"]["hotels"][0].get("summary", [])
]
valid = [r for r in rows if r[1] is not None and (r[2] or 0) > 0]
print(sorted(valid, key=lambda r: (r[1], r[0]))[:10])
```

## Notes

- `lowestTotalPrice` appears to be the total price for the requested rooms/adults/nights in JPY for the displayed Jalan conditions.
- Calendar HTML may only show stock markers; the ZAM JSON summary provides `lowestTotalPrice` directly.
- Always state that the source is Jalan and that live rates can change.
