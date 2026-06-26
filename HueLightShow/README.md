# Hue Light Show

Hue Light Show is a SwiftUI iOS app for running real color-cycle shows on Philips Hue lights through the local Hue Bridge REST API.

## Features

- Discovers Hue Bridges through the Hue discovery broker.
- Pairs with the bridge by creating a local Hue API user after the bridge button is pressed.
- Loads every light returned by the bridge into the light selector.
- Lets you pick the show duration, cycle speed, and editable color list.
- Adds more colors with a plus button.
- Runs the show with one large START button by sending real light state updates to the Hue Bridge.

## Build IPA

Run the `Build Hue Light Show IPA` workflow on GitHub, or push a tag like:

```bash
git tag hue-light-show-v0.1.0
git push origin hue-light-show-v0.1.0
```

The workflow produces `HueLightShow-unsigned.ipa`.

Unsigned IPAs still need signing before installing on a real iPhone.
