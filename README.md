# Resolution Mapper

Resolution Mapper is a small macOS utility for changing, overriding, and mapping external monitor resolution through a virtual display. It was built for stubborn Full HD monitors that feel too large in macOS, but it can be used with any detected external display.

It creates a virtual display, mirrors a selected monitor to it, and stores profiles per monitor using vendor, model, and serial identifiers.

Use it when macOS does not offer the resolution you want in Display Settings, when an external monitor needs more workspace than its native mode exposes, when you want software dimming below the hardware brightness minimum, or when you want a free macOS custom resolution mapper without relying on BetterDisplay.

Keywords people usually search for: macOS resolution override, Mac resolution changer, external monitor custom resolution, virtual display resolution, HiDPI display mapper, QHD on Full HD monitor, change Mac monitor resolution, force display resolution on macOS, Mac brightness below minimum, software screen dimmer for Mac, Mac phone remote, control Mac volume from phone, Mac media keys from phone.

## Features

- Create virtual displays with custom resolutions
- Map any connected external monitor to a selected virtual resolution
- Store resolution profiles per monitor identity
- Use a stable virtual display identity per physical monitor
- Restore saved display arrangement origin after reconnect
- Remove managed virtual displays from the monitor list
- Remove virtual displays automatically when the physical monitor is disconnected
- Restore the saved mapping when the monitor is connected again
- Per-monitor software dimming below the monitor hardware minimum
- Optional LAN phone remote for dimming, volume, and media keys
- QR code phone pairing with persistent authorized phones
- Optional launch-at-login restoration
- Presets for QHD, soft QHD, wide workbench, 4K downsample, and native FHD

## Download

Get the latest universal macOS installer from the [Releases](https://github.com/corekill/ResolutionMapper/releases) page.

## Support

Created by [corekill](https://github.com/corekill).

[![Support Resolution Mapper on Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/corekill)

## Notes

Resolution Mapper uses macOS virtual display APIs. These APIs are not part of a stable public app distribution contract, so behavior may change after macOS updates.

Text smoothing is limited by macOS downscaling and the physical panel. Try less aggressive presets such as `Soft QHD` when text looks jagged.

## Build

```sh
swift build --configuration debug --product ResolutionMapper
```

To create a local universal app bundle and DMG installer:

```sh
CONFIG=debug scripts/build-release.sh
open "dist/Resolution Mapper.app"
open "dist/ResolutionMapper-v1.5.1-macos-universal.dmg"
```

## Attribution

The `VirtualDisplayBridge` target is derived from [SimpleDisplay](https://github.com/SamuelRioTz/SimpleDisplay), which is licensed under GPLv3.

## License

GPLv3. See [LICENSE](LICENSE).
