# LAMZU THORN for Omarchy

An adaptation of the installed [MX Ergo plugin](https://github.com/PavelLizunov/omarchy-mx-ergo), retaining its native two-column panel, Buttons/Pointer/Device pages, named profiles, action picker, recorded shortcuts, command editor, language picker and theme integration.

The mouse diagram has three editable targets: back, forward and middle click. THORN has no wheel-tilt or Bluetooth controls. Main clicks retain their normal behavior. Profiles and pointer settings are saved separately in `~/.config/omarchy/lamzu.json`.

## Source and configuration

Source repository: https://github.com/PavelLizunov/omarchy-lamzu

To obtain a development copy:

```bash
git clone https://github.com/PavelLizunov/omarchy-lamzu.git
```

The source checkout and the installed plugin are separate copies. The installed plugin lives in `~/.config/omarchy/plugins/slovn.lamzu/`; its `manifest.json` selects the active QML entry point, which may live in a versioned runtime subdirectory. Editing a source checkout does not update the installed copy automatically.

Open the LAMZU bar widget and select **Buttons** to remap back, forward or middle click and manage profiles. **Pointer** contains host-side pointer controls; **Device** shows telemetry. Settings are stored in `~/.config/omarchy/lamzu.json`.

This is a source publication, not a Marketplace package or a one-command installer. A new machine requires manual plugin setup and the device permissions described below. The existing installation is not changed by cloning this repository.

## Runtime

The plugin ID remains `slovn.lamzu`. Use the existing Omarchy shell, not a separate Quickshell process. Python 3 and the installed Hyprland Lua device-filter API are required. Individual actions use the same optional tools as MX Ergo: wtype, playerctl, wpctl and the referenced Omarchy plugins/commands.

Settings are host-side Hyprland bindings, not firmware writes. Activation is scoped to `compx-lamzu-thorn-1` and `compx-lamzu-pro-1k-receiver-1`. Pointer settings cover both transports. The keyboard shortcut for switching profiles is global and retains conflict detection.

On Hyprland 0.56.2, removing a handle removes matching key/modifier bindings across press/release edges and devices. Replacement now skips expired handles using the null-safe string representation: calling an expired handle's method can crash the compositor, and Lua `pcall` does not catch that native fault. Both this helper and the MX Ergo companion use the guard. This avoids the identified repeat-unbind path; it does not fix the compositor's cross-device removal semantics. Runtime repair acceptance has not been exercised.

The companion patch in `integration/mx-ergo/apply-settings.py` applies the same device isolation to the installed MX Ergo helper. Its before-snapshot records the exact source changed. Without this patch, the old MX Ergo plugin's global bindings can still react to LAMZU buttons. Reload Hyprland after installing the companion patch to retire pre-existing global callbacks. Disabling either plugin requires a Hyprland reload to retire its runtime bindings.

## Device status

`scripts/telemetry.py` reads CompX report 8 through hidraw. The protocol framing and DPI decoding follow [OpenMouse mouse-protocol](https://github.com/OpenMouse-Project/mouse-protocol). USB `3554:f50f` is preferred over receiver `3554:f50d`; there are no settings or flash writes. A receiver with no responding mouse is not reported as connected. Battery, charging and active DPI are displayed; failures remain explicit rather than becoming 0%.

Polling is once per minute while closed and every 10 seconds while the panel is open. Requests and the complete helper are bounded. Sleep stops telemetry; resume refreshes it and reapplies configured host bindings.

Existing access rules are installed separately at `/etc/udev/rules.d/69-openmouse-lamzu.rules` and `/etc/udev/rules.d/69-openmouse-lamzu-wired.rules`. On another machine install uaccess rules for the two USB IDs before use. The plugin does not elevate itself.

## Delivery status

This source snapshot is adapted from installed MX Ergo runtime `runtime-current-f45d455e8a2e` and published on GitHub. Publication did not run tests, render previews, reinstall the plugin, or exercise live assignments. Earlier basic LAMZU telemetry was observed on the development machine; it does not certify all newly ported profile/editor behavior. No Marketplace publication or verified fresh installation is claimed.

MIT license; the original MX Ergo copyright is retained in LICENSE.
