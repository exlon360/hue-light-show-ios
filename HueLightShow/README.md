# Hue Light Show

Hue Light Show is a SwiftUI iOS app for running real color-cycle shows on Philips Hue lights through the local Hue Bridge REST API.

## Features

- Discovers Hue Bridges through the Hue discovery broker.
- Pairs with the bridge by creating a local Hue API user after the bridge button is pressed.
- Loads every light returned by the bridge into a multi-select light list.
- Lets you pick the show duration, cycle speed, and editable color list.
- Adds more colors with a plus button.
- Supports transition modes: Snap, Gradual, Soft Fade, Pulse, and Blink.
- Supports a bundled `BridgeConfig.plist` for prefilled bridge setup in personal builds.
- Runs the show with one large START button by sending real light state updates to the Hue Bridge.

## Bridge Config

Edit `BridgeConfig.plist` before building a personal IPA if you want the app to come up already pointed at your Hue Bridge after updates.

Set:

- `bridgeAddress`: your bridge IP or host, such as `192.168.1.25`.
- `username` or `applicationKey`: the Hue app key created by bridge-button pairing.
- `selectedLightIDs` or `selectedLightNames`: optional default multi-light selection.
- `selectedLightID` or `selectedLightName`: optional legacy single-light defaults.

Do not commit a real Hue username/application key to a public repo. Keep a private local copy for your own builds.

## Build IPA

Run the `Build Hue Light Show IPA` workflow on GitHub, or push a tag like:

```bash
git tag hue-light-show-v0.1.0
git push origin hue-light-show-v0.1.0
```

The workflow produces `HueLightShow-unsigned.ipa`.

Unsigned IPAs still need signing before installing on a real iPhone.
