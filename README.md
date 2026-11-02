# EmbyFlix

A Netflix-style native macOS client for [Emby](https://emby.media), written in SwiftUI.

**[Download the latest release](https://github.com/J0n4e/Embyfix/releases/latest)**: universal app for Apple Silicon and Intel, macOS 14 or later.

## Install

1. Download `EmbyFlix-vX.Y.zip` from [Releases](https://github.com/J0n4e/Embyfix/releases/latest) and unzip it.
2. Move **EmbyFlix.app** to **Applications**.
3. The first time, right-click the app and choose **Open**. The app is ad-hoc signed, not notarized.

After that, EmbyFlix keeps itself up to date. It checks for new releases at launch and installs them with one click. You can also check yourself under **EmbyFlix → Check for Updates…**.

## Features

### Browsing
- Sign in to one or more Emby servers (http or https). Saved servers can be switched from the sidebar.
- Home page with a rotating featured banner, Continue Watching, and rows for each library.
- Library pages:
  - grid or list view
  - sort and filter (watched, unwatched, genre), with an A–Z jump bar
  - your choices are remembered per library
- Series pages have a season poster row with unwatched counts and an episode grid or list. Movie pages show cast, similar titles and version, audio, subtitle and quality pickers.
- **Actor pages:** click anyone in Cast & Crew to see all their movies and shows in your libraries.
- Favorites and watched/unwatched badges.
- **Now Playing:** every active stream on the server, with its title, position, direct play or transcode, client, device, user and IP.
- Rows scroll with the arrows (one item per click), by dragging with the mouse, or with the trackpad.
- Search across movies, shows and people.

### Player
- Direct play or HLS transcode, with a quality picker. Server transcodes are stopped when you close the player.
- Resume and Start Over, with progress synced to the server.
- **Subtitles:**
  - text subtitles (SRT and others) are drawn by the app; image subtitles (PGS) are burned in by the server
  - adjustable offset, size, colour, shadow, background and position
  - you can always load your preferred language
  - audio and subtitle choices are remembered per series
- **Skip intros automatically** using Emby's intro markers. You can turn this off to get a Skip Intro button instead.
- **Up next card** with a countdown at the end credits.
- **Thumbnail previews** when hovering or dragging the progress bar (uses Emby's generated thumbnails).
- **Chapters** panel (C), **picture in picture** (P) and a **playback info** overlay (I) that shows codecs, bitrate and why the server is transcoding.
- Video-only full screen (F). Esc leaves full screen without stopping the video. In full screen the pointer hides and the screen saver is blocked.
- Keyboard: Space play/pause, ← → skip, F full screen, C chapters, I info, P picture in picture, Esc back.

### Settings (⌘,)
General, Libraries, Series & Episodes, Subtitles, Playback, Servers, and About with the update controls.

> Intro skipping and thumbnail previews depend on your Emby server: intro detection and thumbnail-image extraction must be enabled there.

## Build from source

Requires macOS 14+ and Xcode 15+ (Swift 5.9).

```sh
swift run                 # run in development
./make-app.sh             # build dist/EmbyFlix.app (universal, ad-hoc signed)
VERSION=v1.4 ./make-app.sh   # set the version shown in the app (default: latest git tag)
```

## Development and releases

- Work goes to the **`Development`** branch through pull requests. `Development` is merged into `main` for each release.
- Releases are built by the **Build EmbyFlix.app** GitHub Actions workflow, which you start by hand (*Run workflow*, with the version, for example `v1.5`). The workflow's zip is attached to a GitHub release. Full releases are what the in-app updater installs; pre-releases are ignored.

## License

See [LICENSE](LICENSE).
