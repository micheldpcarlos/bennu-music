My iPad 2 has been in a drawer for years. iOS 9.3.5, an App Store with nothing left to install, a browser that can't load most of today's websites, and no Spotify.

So I built one. Bennu Music is a native Spotify player for jailbroken 32-bit iOS devices. It works as a Spotify Connect speaker from your phone, and as a full player on the device itself: search, library, queue, lock-screen controls, and the Windows Media Player 9 visualizations I grew up with, redrawn for a 2011 CPU.

What it took: porting an open-source Spotify Connect engine to a 2016 toolchain (C++14, the old libc++), reverse-engineering the endpoints the official clients use because the public API rate-limits this kind of client, a QR sign-in flow that works with no computer in the loop, and keeping it all smooth on a 2011 CPU with 512 MB of RAM.

Open source, GPL-3, installs from a .deb. If you have an old iPad or iPhone 4S/5 somewhere, it can be a music player again. Mine now runs the music in the pool house, plugged into the stereo with an aux cable 🎶🔊

github.com/micheldpcarlos/bennu-music

#ios #spotify #opensource #embedded #retrocomputing

---

## Alt text for the carousel

1. Now Playing: Bennu Music on an iPad 2: Now Playing screen with Daft Punk's Random Access Memories cover, a progress bar, and play, skip, shuffle and repeat controls.
2. Album page: Album page for Random Access Memories by Daft Punk on an old iPad: cover, Play and Shuffle buttons, and a numbered track list with the current song in green.
3. Welcome screen: Bennu Music welcome screen: a QR code and pairing code to sign in from a phone, an option to pick the iPad from Spotify's device list, and a "Visible on this network" switch.
4. Visualization picker: Now Playing with the visualization picker open: families like Alchemy, Ambience and Battery on the left, presets on the right, Smokey Circles selected.
5. Plenoptic visualization: Full-screen music visualization: soft overlapping rings in green, orange and red, smearing across the screen, in the style of Windows Media Player 9.
6. Spikes visualization: Full-screen music visualization: a ring of yellow spikes tipped with dots radiating from a black center, their length following the music.
