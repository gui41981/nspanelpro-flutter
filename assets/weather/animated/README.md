# Animated weather icons

The weather card requests animated WebP files from the NAS web server by default:

`http://192.168.1.95/nspanel-weather/animated/`

The corresponding SMB directory is:

`/run/smb4k/guillaume/nas/web/nspanel-weather/animated/`

Place one transparent, looping animated WebP per Home Assistant condition, using these exact filenames:

- `sunny.webp`
- `clear-night.webp`
- `partlycloudy.webp`
- `cloudy.webp`
- `fog.webp`
- `hail.webp`
- `lightning.webp`
- `lightning-rainy.webp`
- `rainy.webp`
- `pouring.webp`
- `snowy.webp`
- `snowy-rainy.webp`
- `windy.webp`
- `windy-variant.webp`
- `exceptional.webp`

The app downloads icons to its application-support cache and refreshes them after 24 hours. A cached copy is kept when the NAS is temporarily unavailable. Missing or invalid files fall back to the built-in MDI icon.

The original artwork can also be stored in this repository under `assets/weather/animated/` if the project later embeds the icons in the APK. Keep the artwork's original licence and attribution alongside those files.

To override the NAS address, set the weather card's `animated_icon_url` to another absolute URL or server-relative path.
