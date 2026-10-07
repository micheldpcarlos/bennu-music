# Catalog search without the public Web API — research, 2026-10-07

Background: `GET api.spotify.com/v1/search` with the CSpot login5 token (web-player client id) returns HTTP 429 every time. The Feb/Mar 2026 Web API changes and the 2026-07-23 quota update make 429 the expected answer for a token that does not belong to a registered developer app. Options that use only the session CSpot already has:

## 1. spclient context-resolve with a search URI — try first

```
GET https://<spclient host from apresolve>/context-resolve/v1/spotify:search:never+gonna+give
Authorization: Bearer <login5 token>
```

- Same token AccessKeyFetcher already obtains for playback; librespot and go-librespot use it for spclient.
- Response is a Context JSON: track URIs in `pages[0].tracks[].uri`, about 20 per query, tracks only (no albums/artists/playlists). Names come from a follow-up metadata call (`/metadata/4/track/<hex gid>` or extended-metadata).
- `client-token` header is optional in both reference clients (librespot logs a warning and continues without it). Test once without it.
- Evidence: rzcastilho/mod-player, live probes 2026-09-17 against a Premium account, "succeeded reliably":
  https://github.com/rzcastilho/mod-player/blob/main/specs/004-search-and-library-browse/research.md
- Cost: one HTTPS GET plus one metadata request. Removes the second OAuth flow, the phone and the developer-app quota from catalog search entirely.

## 2. Pathfinder GraphQL — works, expensive

`api-partner.spotify.com/pathfinder/v1/query`, `operationName=searchDesktop`, persisted-query sha256 hash, headers `Authorization: Bearer`, `client-token`, `app-platform: WebPlayer`, origin/referer `https://open.spotify.com`. Returns albums/artists/playlists too. Requires a client-token (protobuf POST to `clienttoken.spotify.com/v1/clienttoken`, portable from go-librespot) and the query hashes rotate with web-player releases. No librespot-family client ships it (go-librespot issue #311, May 2026, open). Only worth it if non-track search is needed.

## 3. Mercury `hm://searchview/km/v4/search/` — dead

Returns Unavailable as of 2026-09 (mod-player probes). librespot never implemented it; librespot-java's SearchManager is archived. Skip.

## Plan

1. Still run `token-test/search-probe.py` once: it is cheap and tells us whether the own-app Web API path is even available as a fallback.
2. Add a context-resolve probe to CatalogSearch behind the existing diagnostics (`CATALOG: ...` lines, same cooldown policy), keeping the Web API path selectable until one is proven on device.
3. If context-resolve returns tracks, hydrate names via metadata, drop the own-app OAuth plan for search, and keep the QR flow for playback account recovery only.
