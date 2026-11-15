# API notes

The Iran Seda service has no public API documentation. These notes describe what the app uses, found by
reading the responses of the public service. They can break whenever the service changes.

Host: `https://apisec.iranseda.ir`. Links in responses that point at `http://api.iranseda.ir` are the same
API over plain HTTP; the app rewrites them to the HTTPS host.

## Server-driven navigation

The app loads one entry point and then only follows links found in responses. It does not build URLs itself.

| Step | Link | Returns |
| --- | --- | --- |
| Start | `/initv8/?VALID=TRUE` | `Base[]`: hubs, each with `tabs[]` (`FeedAddress`) |
| Radio | hub with `UrlType == "radio"` → `/radio/` | `channels[]`, each with `tabs[]` (type 1 live, 2 schedule, 3 programmes, 4 time archive) |
| Feed | any `FeedAddress` or `MoreLink` | `Containers[]` → `boxes[]` (`URL`, `URLType`) |
| Item | box with `URLType` 9 | player detail: `items[]` with `playUrl` (HLS) and `download[]` |
| Serial or programme | box with `URLType` 7 | header plus `tabs[]` of further feeds |
| Live stream | `PlayURL` from a station's on-air info | player detail with `type: "live"` |

## Quirks

- Responses contain raw control characters inside strings and are not strict JSON; `API.sanitize` cleans them.
- Fields are strings, sometimes numbers, often missing. All decoding is lenient (`Lossy`, `LossyList` in `Models.swift`).
- Some streams, downloads and images are plain HTTP, so App Transport Security is opened up in `project.yml`.

## Paging

A feed whose response says `"Infinity": "true"` has more pages. The next page is the same link with
`pn=2`, then `pn=3`, and so on (`PageNo` in the response confirms the page). A page that only repeats
earlier items means the list has ended.

## Radio programmes

A programme home (`/radio/ProgramHome/`) has tabs. Type 7 is what is on air now, type 1 is past episodes:
`{"episodes": [{day, month, year, description1, duration (seconds), PlayURL}]}`. `PlayURL` returns a normal
player detail whose `items[]` are the half-hour parts of that broadcast, each downloadable.

## Unknown

- The search call. The Android app receives a search link from the server (`SearchURL`), but where that
  comes from is not known. The app therefore searches on the device: all stations, plus the front shelves
  of every hub.
- Playing from a time in the archive (`PlayUrlByTime`) is assumed to return a player detail; not verified.
- Comments, likes, contests and programme staff lists are not used.

## Being a good client

Requests are made only when a screen opens or is refreshed. Please keep it that way: no crawling, no
background polling, no bulk downloading.
