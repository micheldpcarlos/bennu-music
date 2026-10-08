# Changelog

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
