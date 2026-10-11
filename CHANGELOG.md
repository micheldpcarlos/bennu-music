# Changelog

## 0.5.1 (2026-10-11)

- **Fixes crashes during track changes.** When the connection to Spotify's audio servers
  dropped while opening or reading a song, an unhandled network error aborted the app. Stream
  opens now retry and then skip the track; reads retry on a fresh connection.
- **Fixes playlist search.** Search fell back to songs only because a playlist owner name was
  cut in the middle of a UTF-8 character.
- **Stays in sync with your phone.** The player now publishes its real queue to Spotify, so the
  phone's "next up" matches what plays; the shuffle and repeat toggles from the phone reorder
  and replan the queue; turning shuffle off restores the original order. After a reconnect the
  player re-announces what it is playing instead of appearing idle.
- **Fewer disconnects.** The access point's keep-alive is answered like the official clients
  (pong after 60 s, empty payload); the immediate echoed pong made the server drop the session
  every few minutes to hours.
- Shuffle in Now Playing now acts on what is playing and reflects the phone's setting; the
  Queue screen shows the order actually played.

## 0.5.0 (2026-10-08)

- **Settings** (Account › Settings): audio quality (96 / 160 / 320 kbps, restarts the player),
  network visibility, clear cached data with its size, version and update check, diagnostics
  export, links to the project.
- **Updates.** Home checks GitHub once per launch and says when a newer release exists.
  Settings downloads the `.deb` to `/var/mobile/Downloads` and opens it in Filza for a
  one-tap install, with the `dpkg` command shown when Filza is absent.
- **Cydia / Sileo source** at https://micheldpcarlos.github.io/bennu-music/ for installs and
  updates through a package manager.
- **Diagnostics export** writes a copy of the player's log with credentials removed and opens
  the share sheet, for bug reports.
- A daily GitHub Action refreshes `config/pathfinder.json` from the live web player so hash
  rotations are fixed for every installed app without a release.

## 0.4.0 (2026-10-08)

- **Home is Spotify's own Home.** Daily Mixes, Made For You, Jump back in, Recently played,
  Recommended Stations, Your top mixes and the "For fans of" shelves come from the web player's
  Home feed, with Spotify's greeting. The previous derived shelves remain as the fallback.
- **Your Library shows everything saved**: playlists, albums and followed artists, with
  All / Playlists / Albums / Artists filters and Liked Songs with its count. The rootlist and
  recently played remain as the fallback.
- The search service now discovers hashes for every web player operation in one pass, so new
  features can be added without touching the hash machinery; `config/pathfinder.json` is a map.
- User playlist covers from the web player's CDN are rewritten to the JPEG form iOS 9 can decode.

## 0.3.0 (2026-10-08)

- Search now uses the web player's search service and returns songs, artists, albums and
  **playlists** directly, in one call, with no per-track metadata fetches. Artists and albums
  are real search hits instead of being derived from matching songs.
- The service depends on a query hash that Spotify rotates with web player releases. The app
  keeps the last working hash, and when it stops working it tries, in order: a config file in
  this repository, scraping the web player's JavaScript on the device, and the hash compiled
  into the release. If all of that fails, search falls back to the previous track-only path.
- A `pathfinder` kill switch in `bennu-catalog-flags.json` disables the new path; three
  consecutive failures pause it for ten minutes.
- Refreshing the hash on the device takes about two seconds (page, main bundle, search chunk);
  it also runs in the background once a week. A client token for the service is obtained
  automatically and renewed every two weeks.
- Fixes the HTTP client's header reader for very long headers; chunked responses from any host.

## 0.2.1 (2026-10-08)

- Fixes an intermittent crash while typing in Search: a replaced request stayed in the
  catalog client's polling list after it was freed.
- Crashes now write the exception or signal and a backtrace to `Documents/cspot-app.log`,
  since these devices have no crash reporter.

## 0.2.0 (2026-10-08)

- Runs on iPhone and iPod touch as well as iPad: iPhone 4S, iPhone 5, iPhone 5c and iPod
  touch (5th generation) are now accepted, with layouts for 320-point screens and launch
  images so the app is not letterboxed. Phone layouts were verified at phone sizes on an
  iPad; reports from real phones are welcome.
- Now Playing: visualizer and queue buttons form a bottom action row.
- Fixes: Your Library loaded only after the next track change; the position carried over
  from the previous track on natural transitions; the Connect volume read as zero on the phone.

## 0.1.0 (2026-10-08)

First public release.

- Spotify Connect receiver ("Bennu Music" in the phone's device list) and standalone player
  for jailbroken 32-bit devices on iOS 9.3.5.
- Sign in by scanning a QR code (Spotify's device-authorization flow) or by pairing from the
  Spotify app on the same network.
- Home, Search with browse categories and filters, Your Library, album, playlist, artist and
  Liked Songs pages, queue with play-next, repeat and shuffle.
- Now Playing with seek, lock-screen and Control Center controls, and the Windows Media
  Player 9 visualization catalog with a Shuffle-all mode.
- Phone volume slider mirrors the iPad's system volume in both directions.
- Automatic reconnect, engine restart with backoff and per-feature degradation when Spotify
  changes an endpoint.
