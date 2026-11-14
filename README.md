# Iran Seda for iOS (private use)

A SwiftUI client for the Iran Seda (IRIB radio) service, built against the same
API the Android app (`ir.newiranseda`, v4) uses.

## Build

```sh
brew install xcodegen
xcodegen            # creates IranSeda.xcodeproj from project.yml
open IranSeda.xcodeproj
```

In Xcode: select the IranSeda target, set your Team under Signing & Capabilities,
pick your iPhone, Run. Needs iOS 17+.

## What it does

- Live radio: every national and provincial station (HLS).
- Per station: on-air info, schedule, programme list, hour-by-hour archive.
- Hubs listed by the server: audiobooks, podcasts, kids, Quran, music, talks, etc.
- Player: background audio, lock-screen controls, 15 s skip, resume position per file, sleep timer.
- Offline: download a file from its detail page; play it from the Downloads tab.

## How the API works

Host: `https://apisec.iranseda.ir` (the app's `http://api.iranseda.ir` links are rewritten to it).

The API is server-driven. The app loads one entry point and then only follows
links from responses:

| Step | Link | Returns |
| --- | --- | --- |
| Start | `/initv8/?VALID=TRUE` | `Base[]`: hubs, each with `tabs[]` (`FeedAddress`) |
| Radio | hub with `UrlType == "radio"` → `/radio/` | `channels[]`, each with `tabs[]` (type 1 live, 2 schedule, 3 programmes, 4 time archive) |
| Feed | any `FeedAddress` / `MoreLink` | `Containers[]` → `boxes[]` (`URL`, `URLType`) |
| Item | box with `URLType` 9 | player detail: `items[]` with `playUrl` (HLS) and `download[]` |
| Serial / programme | box with `URLType` 7 | header plus `tabs[]` of further feeds |

Quirks handled in `Core/API.swift` and `Core/Models.swift`:

- Responses contain raw control characters inside strings; they are cleaned before decoding.
- Fields are strings, sometimes numbers, often missing; all decoding is lenient.
- Some streams and images are plain HTTP, so App Transport Security is opened up in `project.yml`.

## Not done

- Search, paging of long lists (only the first page loads), comments, likes, login, CarPlay.
- The code has not been compiled yet; it was written without Xcode.
