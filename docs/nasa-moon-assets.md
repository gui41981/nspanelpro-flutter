# NASA Moon overlay assets

The 30 bundled JPEGs are daily samples from NASA Scientific Visualization Studio,
**Moon Phases Loop** (SVS ID 4310), visualizations by Ernie Wright.

- Official source: https://svs.gsfc.nasa.gov/4310/
- NASA SVS states that its visualization content is public domain unless otherwise noted:
  https://svs.gsfc.nasa.gov/help/
- Frame sequence: 236 frames over an average 29.5-day synodic month, at 3-hour
  intervals. NASA documents the mapping as `frame = (days × 8) + 1`.
- This app bundles frames 1, 9, 17, …, 233: one sample per lunar day.
- The source visualization is geocentric with lunar north up. It is an idealized
  phase sequence and does not model libration or subsolar latitude.

The app asks the NASA Dial-A-Moon API only for the current lunar age; the image
itself is loaded from these bundled assets, so the display does not depend on
NASA's image host being reachable from the panel.
