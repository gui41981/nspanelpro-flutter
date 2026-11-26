# Animated weather icons

The weather card uses the original pack of nine transparent, looping animated
WebP icons. By default, it requests them from the NAS web server:

`http://192.168.1.95/nspanel-weather/animated/`

The corresponding SMB directory is:

`/run/smb4k/guillaume/nas/web/nspanel-weather/animated/`

Place these nine files in that directory:

- `sunny.webp`
- `storm.webp`
- `partly-cloudy.webp`
- `rainy.webp`
- `cloudy.webp`
- `snow.webp`
- `tornado.webp`
- `foggy.webp`
- `sleet.webp`

Home Assistant conditions are mapped to the closest matching illustration:
sunny/clear, partly cloudy, cloudy, fog, hail, lightning and rain, rain,
snow, snow/rain, and exceptional weather. Clear-night and windy conditions
keep their built-in MDI icons because this pack has no matching night or wind
illustration. Missing or invalid WebP files also fall back to MDI.

The app downloads icons on demand to its application-support cache and
refreshes them after 24 hours. A cached copy is kept when the NAS is
temporarily unavailable.

The original artwork can also be stored in this repository under
`assets/weather/animated/` if the project later embeds the icons in the APK.
Keep the artwork's original licence and attribution alongside those files.

To override the NAS address, set the weather card's `animated_icon_url` to
another absolute URL or server-relative path.
