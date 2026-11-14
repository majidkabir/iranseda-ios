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

## Unknown

- How long lists are paged (`Infinity`, `PageNo`, `ItemPerPage` appear in responses).
- The parameters of the search endpoint.
- Response formats of a radio programme's episode list and of archive playback are assumed, not verified.

## Being a good client

Requests are made only when a screen opens or is refreshed. Please keep it that way: no crawling, no
background polling, no bulk downloading.
