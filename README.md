# Squish for iPhone

A native wrapper around https://squish-video.vercel.app: full-screen, no browser bars,
and **Save to Photos** puts the finished video straight into your camera roll.
If Photos can't take the file (e.g. WebM), the share sheet opens instead so you can use "Save to Files".

## How it's built
- `Sources/` – SwiftUI app with one `WKWebView` that loads the live site, and the native save code.
- `Resources/inject.js` – injected into the site inside the app: catches the Download click,
  streams the video to native code in 3 MB pieces, relabels the button, and adjusts spacing for touch.
  The website itself is not changed.
- `project.yml` – XcodeGen project (name, bundle id, permissions, iOS 16.4+).
- `.github/workflows/build.yml` – builds an **unsigned** `.ipa` on GitHub's free Mac runners on every
  push to `main`, and attaches it to the `latest` release.

## Getting the .ipa
GitHub repo → **Releases → Latest build → Squish.ipa** (or Actions → latest run → `Squish-ipa`).
Sign and install it with ESign, Sideloadly, or similar.

## Reusing it for another site
Change `homeURL` in `Sources/WebViewController.swift`, the name/bundle id in `project.yml`,
the icon in `Resources/Assets.xcassets/AppIcon.appiconset/icon.png`, and adjust or remove the
site-specific parts of `Resources/inject.js`.
