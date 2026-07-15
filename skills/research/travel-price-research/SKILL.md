---
requires_tools: [hermes_terminal]
name: travel-price-research
description: "Find cheapest hotel/travel dates from booking sites and public booking data; compare date ranges, availability, prices, and assumptions."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [travel, hotels, booking, prices, availability, scraping]
    related_skills: [maps, web-endpoint-monitoring]
---

# Travel Price Research

## Overview

Use this skill when the user asks for the cheapest dates, availability, or price comparison for hotels, flights, events, or travel bookings across a date range. The output must be grounded in live retrieval from an accessible source, with assumptions stated clearly.

The common pattern is: identify the property/product, find an accessible source with date-level prices, fetch a full date range programmatically when possible, parse normalized rows, then report the cheapest dates and near-cheapest alternatives.

## Standard Workflow

1. **Clarify only if the default would materially change the answer.** If the user says "cheapest day in July–August" and does not specify guests/rooms, use an obvious default such as 1 night, 1 room, 2 adults, then state it. Ask only if party size, stay length, or room type is central.

2. **Find an accessible authoritative or reputable source.** Prefer official booking APIs/pages, then major OTAs. Use optional web-search or browser integrations for discovery when available; otherwise start from a user-provided source or retrieve official endpoints directly through the terminal. If one source blocks automated access, try another source before giving up. Do not fabricate prices from snippets.

3. **Probe one date first.** Confirm the source returns the target property and the expected fields: date, price, availability/stock, currency, taxes/fees meaning if available.

4. **Fetch the full requested range in chunks.** Many booking APIs limit range length. Use monthly chunks when uncertain. Normalize dates to ISO `YYYY-MM-DD`, prices to integers/decimals, and retain stock/availability.

5. **Filter to valid sellable dates.** Exclude dates with no stock, missing price, sold out, or explicit errors. Keep a note of dates omitted because no price was returned.

6. **Rank and report.** Show the minimum date(s), price, and stock/availability. Include a small top-N table and the assumptions/source. If prices can change, say they are live at retrieval time.

7. **Verify the result.** Re-run or sanity-check the minimum dates against a second request/source when practical. At minimum, confirm the returned hotel/property ID/name matches the user’s hotel.

## Implementation Notes

- Use terminal/Python for range fetching and parsing; avoid hand-checking dozens of dates in a browser.
- Preserve source-specific details in `references/` when a reusable endpoint or parsing trick is discovered.
- Be careful with booking-site anti-bot pages and HTTP 403/202 challenge pages. A successful HTTP status is not enough; verify the body contains the target hotel/price data.
- Do not treat one source's price as universal. Label it as "Marriott", "Jalan", "Booking.com", etc.
- If the user needs booking advice, include nearby dates within a small price delta, not only the absolute minimum.

## Known Source Techniques

- **Jalan hotel pages** can expose a ZAM availability API usable for date-range price summaries. See `references/jalan-zam-hotel-prices.md`.

## Output Template

```markdown
調べた条件では、最安日は **YYYY年M月D日(曜)** でした。

| 順位 | 日付 | 最安料金 | 空室/在庫 |
|---:|---|---:|---:|
| 1 | **YYYY/MM/DD(曜)** | **¥NN,NNN** | N |
| 2 | YYYY/MM/DD(曜) | ¥NN,NNN | N |

前提条件:
- Source: <site/source>
- 条件: 1泊 / 1室 / 大人2名 / <その他>
- 対象期間: <range>
- 料金は取得時点の表示価格で、変動する可能性があります。
```

## Pitfalls

1. **Search snippets are not enough.** They may show stale minimum prices or unspecified dates. Use them only to discover candidate sources.
2. **Date range off-by-one.** Hotel check-in dates are the dates to rank; checkout is check-in plus stay length.
3. **Character encoding.** Japanese OTA pages may be Shift_JIS/CP932 even when other parts are UTF-8.
4. **Availability vs. price.** A low price without stock is not bookable; retain and report availability/stock where available.
5. **Hidden defaults.** Always state guests, rooms, stay length, source, and whether taxes/fees are included if known.

## Verification Checklist

- [ ] Target property identity confirmed by ID/name.
- [ ] Date range fully covered or omissions listed.
- [ ] Prices parsed from live source data, not snippets.
- [ ] Sold-out/missing-price dates excluded from cheapest ranking.
- [ ] Source, party size, rooms, nights, and currency stated.
