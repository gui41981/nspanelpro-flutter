# Moon overlay

When Home Assistant reports `sun.sun = below_horizon`, the WeatherProCard
requests the current day's Moon data from Moonphases.co.uk and displays its
published image. The API response supplies the image filename and local
orientation (`tilt`), so the card uses the site's actual daily artwork rather
than a locally bundled phase approximation.

The request is made when the night overlay is created; it is not polled hourly.
The image is loaded directly from `https://moonphases.co.uk/images/moons/`.
