# Trackball icon

`trackball.svg` is the approved simplified B design for MX Ergo: a solid ergonomic body, a large thumb ball, and one button divider. It was drawn as SVG for small status-bar sizes and is covered by the repository MIT license.

The white source is tinted with the active Omarchy foreground color in `BarWidget.qml`. The ball clearance and button divider are transparent cutouts. The SVG is bundled locally; displaying it makes no network requests.

The body is vertically compressed by 10% and centered in the canvas to match the neighboring bar icons. The thumb ball remains circular.

## Button diagram

`trackball-map.png` is the generated product illustration extracted from the approved third button-mapping concept. It has an alpha background and is bundled locally. The built-in image generator produced the cutout from the approved concept with the instruction to preserve the MX Ergo geometry and remove UI overlays and background.

`TrackballMap.qml` draws all labels, callout lines and selectable targets separately using the host theme. No assignment is baked into the image. Its normalized button coordinates refer to this exact 1024 × 1536 image, including transparent margins; replacing or cropping the image requires rechecking those coordinates.

The illustration identifies compatible hardware; Logitech and Logi marks belong to their respective owner. This community plugin is not an official Logitech application.

## Screenshots

`screenshots/current/` contains the current actual `ErgoPanel.qml` consumer renders
at native logical density (736 × 650), with inert example data, installed shell
controls and controlled light/dark palettes. `evidence.json` identifies the
candidate, inputs and images. These are offscreen QML captures, not live desktop
screenshots or proof of Bluetooth state. The root `preview.png` uses the current
light-theme Buttons render.

`screenshots/original/` contains earlier supplied UI captures;
`screenshots/qml-2x/` contains historical 2× QML rerenders matching those captures.
They describe an older layout and are retained separately for provenance.

The screenshots show Logitech and Logi product marks for hardware identification. Those marks remain the property of their respective owners; the repository license does not grant rights to third-party marks. This community plugin is not an official Logitech application.
