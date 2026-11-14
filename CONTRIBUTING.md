# Contributing

Thanks for helping. This is a small hobby project, so the process is light.

## Before you start

- For anything larger than a small fix, open an issue first so we can agree on the approach.
- Bugs: say what you did, what you expected, what happened, and your iOS version.

## Set up

```sh
brew install xcodegen
xcodegen
open IranSeda.xcodeproj
```

The Xcode project is generated, so it is not in git. Change `project.yml`, not the project file.

Run with the launch arguments `-demo YES` to use built-in sample data instead of the network.
`-screen <name>` opens a specific screen (`home`, `radio`, `channel`, `hub`, `detail`, `player`, `library`,
`downloads`, `settings`); see `Core/Demo.swift`.

## Pull requests

- Branch from `main`, keep a pull request to one change.
- CI must pass: it builds the app for the iOS Simulator.
- For UI changes, push to a branch named `ui/<something>`. A workflow then captures every screen in light,
  dark and large-text modes and publishes the pictures to the `screenshots` branch. Add before and after
  pictures to the pull request.
- User-facing text is Persian and the layout is right-to-left. Show numbers with `Format.fa`.
- New screens need to work with VoiceOver labels, dark mode and large text sizes.

## What not to add

- Content, logos or code taken from the official app or the service.
- Anything that scrapes, crawls or bulk-downloads from the service. See "Being a good client" in
  [docs/API.md](docs/API.md).
- Tracking, analytics or accounts. The app keeps everything on the device.

## Licence

By contributing you agree that your work is released under the [MIT licence](LICENSE).
