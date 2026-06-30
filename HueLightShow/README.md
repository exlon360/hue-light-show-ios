# Hue Light Show

Hue Light Show is a SwiftUI iOS app for running real color-cycle shows on Philips Hue lights through the local Hue Bridge REST API.

## Features

- Discovers Hue Bridges through the Hue discovery broker.
- Pairs with the bridge by creating a local Hue API user after the bridge button is pressed.
- Loads every light returned by the bridge into a multi-select light list.
- Lets you pick a timed or infinite show, cycle speed, and editable color list.
- Adds colors with a plus button and removes colors with the `x` button beside each swatch.
- Adds a Global Pattern picker with `Together` and `Fairy Lights`; Fairy Lights maps bulb 1 to color 1, bulb 2 to color 2, and keeps rotating.
- Lets selected lights follow the shared Global Lights Group or switch to their own custom colors and transition.
- Keeps the screen awake while a show runs and asks iOS for background time if the app is backgrounded.
- Supports transition modes: Snap, Gradual, Soft Fade, Pulse, and Blink.
- Supports a bundled `BridgeConfig.plist` for prefilled bridge setup in personal builds.
- Runs the show with one large START button by sending real light state updates to the Hue Bridge.

## Global And Custom Lights

Every selected light starts in the Global Lights Group. Change the Global Lights Group once and every global light follows it.

Tap `Custom` under a selected light to give that light its own color cycle and transition. Tap `Global` again to put it back into the shared Global Lights Group.

Global and custom lights run together when START is tapped. Custom lights are removed from the Global Lights Group at runtime and each custom light gets its own color cycle, transition, and timing state.

The Global Pattern setting only affects lights that are still in the Global Lights Group. Custom lights keep their own custom colors and transition.

## Infinite Shows And Backgrounding

Turn on `Infinite` to run until STOP is tapped. iOS does not allow a fully closed or force-quit app to keep sending Hue commands forever, so keep the app open for true infinite shows. The app keeps the screen awake while running and requests limited background time if it is sent to the background.

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
