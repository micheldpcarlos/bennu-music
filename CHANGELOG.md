# Changelog

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
