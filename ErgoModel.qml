import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "I18n.js" as I18n
import "ButtonProfiles.js" as Profiles

// Single state owner for LAMZU THORN mouse.
// Bounded CompX telemetry and device-scoped Hyprland pointer/button controls.
QtObject {
  id: root

  property string hyprDeviceName: "compx-lamzu-thorn-1"
  property string language: "system"
  readonly property string effectiveLanguage: I18n.resolveLanguage(language, Qt.locale().name)

  signal localeRequested(string code)

  function setLocale(code) {
    if (["system", "en", "ru", "de", "fr", "es", "it", "pt", "zh", "ja", "ko"].indexOf(code) < 0) return
    root.language = code
    root.localeRequested(code)
  }

  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  readonly property string configPath: configHome + "/omarchy/lamzu.json"
  readonly property string configHelper: decodeURIComponent(Qt.resolvedUrl("scripts/config-store.py").toString().replace(/^file:\/\//, ""))

  // User adjustable pointer settings
  property real sensitivity: 0.0
  property string accelProfile: "adaptive"
  property bool naturalScroll: false
  property bool configReadComplete: false
  property bool settingsConfigured: false
  property bool configLoadFailed: false
  property bool configSaveFailed: false
  property bool configWriting: false
  property bool configStored: false
  readonly property bool configPending: saveDebounce.running || configWriting || pendingConfig !== ""
  property bool sleeping: false
  property bool shuttingDown: false
  property bool sleepMonitorFailed: false
  property int sleepMonitorRestarts: 0

  // Theme changes reload Hyprland and discard settings applied via hyprctl eval.
  property Connections hyprlandEvents: Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && event.name === "configreloaded" && root.configReadComplete && root.settingsConfigured) {
        console.info("LAMZU THORN: restoring settings after Hyprland reload")
        root.applyAllSettings()
      }
    }
  }

  property bool panelOpen: false
  onPanelOpenChanged: if (panelOpen) refreshTelemetry()

  // User configurable button actions
  property string buttonBack: "default"
  property string buttonForward: "default"
  property string buttonMiddle: "default"
  property string buttonTiltLeft: "default"
  property string buttonTiltRight: "default"

  // User custom shortcut key combinations (e.g. "CTRL + SHIFT + T")
  property string buttonCustomShortcutBack: ""
  property string buttonCustomShortcutForward: ""
  property string buttonCustomShortcutMiddle: ""
  property string buttonCustomShortcutTiltLeft: ""
  property string buttonCustomShortcutTiltRight: ""

  // User custom shell commands (e.g. "alacritty", "omarchy-menu toggle")
  property string buttonCustomCmdBack: ""
  property string buttonCustomCmdForward: ""
  property string buttonCustomCmdMiddle: ""
  property string buttonCustomCmdTiltLeft: ""
  property string buttonCustomCmdTiltRight: ""

  // The active properties above are the editor's view of one profile.
  property var buttonProfiles: []
  property string activeProfileId: "main"
  property string profileShortcut: ""
  property var profileTransaction: null
  property string profileError: ""
  property string profileRetryId: ""
  property string profileRetryRemoveId: ""
  property double profileLastSwitchAt: 0
  readonly property bool profileBusy: profileTransaction !== null
  readonly property string activeProfileName: {
    var item = Profiles.find(root.buttonProfiles, root.activeProfileId)
    return item ? item.name : root.t("profile_main")
  }

  function captureButtonProfile() {
    var item = Profiles.profile(root.activeProfileId, root.activeProfileName, null)
    Profiles.keys.forEach(function(key) {
      item.buttons[key] = root.getButtonAction(key)
      item.customShortcuts[key] = root.getCustomShortcut(key)
      item.customCommands[key] = root.getCustomCommand(key)
    })
    return item
  }

  function storeActiveProfile() {
    var item = root.captureButtonProfile()
    if (!root.buttonProfiles.length) root.buttonProfiles = [item]
    else root.buttonProfiles = root.buttonProfiles.map(function(p) { return p.id === item.id ? item : p })
  }

  function loadButtonProfile(item) {
    var names = {back: "Back", forward: "Forward", middle: "Middle", tiltLeft: "TiltLeft", tiltRight: "TiltRight"}
    Profiles.keys.forEach(function(key) {
      var name = names[key]
      root["button" + name] = item.buttons[key]
      root["buttonCustomShortcut" + name] = item.customShortcuts[key]
      root["buttonCustomCmd" + name] = item.customCommands[key]
    })
  }

  function loadProfileConfig(cfg) {
    var data = Profiles.fromConfig(cfg, root.t("profile_main"))
    root.buttonProfiles = data.profiles
    root.activeProfileId = data.activeProfileId
    root.profileShortcut = data.profileShortcut
    root.loadButtonProfile(Profiles.find(data.profiles, data.activeProfileId))
  }

  function validProfileName(name) {
    var value = String(name || "").trim()
    return value.length > 0 && value.length <= 80 && !/[\u0000-\u001f]/.test(value) ? value : ""
  }

  function createProfile(name) {
    if (!root.configReadComplete || root.profileBusy || root.sleeping || root.shuttingDown
        || root.buttonProfiles.length >= Profiles.maxProfiles) return false
    var value = root.validProfileName(name)
    if (!value) { root.profileError = "profile_invalid_name"; return false }
    root.storeActiveProfile()
    var base = "profile-" + Date.now().toString(36)
    var id = base
    for (let serial = 1; Profiles.find(root.buttonProfiles, id); serial++) id = base + "-" + serial
    var item = Profiles.profile(id, value, root.captureButtonProfile())
    root.buttonProfiles = root.buttonProfiles.concat([item])
    return root.selectProfile(id)
  }

  function renameProfile(name) {
    if (!root.configReadComplete || root.profileBusy) return false
    var value = root.validProfileName(name)
    if (!value) { root.profileError = "profile_invalid_name"; return false }
    root.storeActiveProfile()
    root.buttonProfiles = root.buttonProfiles.map(function(item) {
      var result = Profiles.copy(item)
      if (result.id === root.activeProfileId) result.name = value
      return result
    })
    root.profileError = ""
    saveDebounce.restart()
    return true
  }

  function deleteProfile() {
    if (root.profileBusy || root.buttonProfiles.length <= 1) return false
    var index = root.buttonProfiles.findIndex(function(p) { return p.id === root.activeProfileId })
    var next = root.buttonProfiles[(index + 1) % root.buttonProfiles.length]
    return root.selectProfile(next.id, root.activeProfileId)
  }

  function selectProfile(id, removeId) {
    if (!root.configReadComplete || root.profileBusy || root.sleeping || root.shuttingDown) return false
    root.storeActiveProfile()
    if (!Profiles.find(root.buttonProfiles, id) || id === root.activeProfileId) return false
    root.profileTransaction = {fromId: root.activeProfileId, toId: id,
      fromShortcut: root.profileShortcut, toShortcut: root.profileShortcut,
      removeId: removeId || "", rollback: false}
    root.profileError = ""
    root.profileRetryId = ""
    root.profileRetryRemoveId = ""
    root.applyAllSettings()
    return true
  }

  function nextProfile(fromWheel) {
    var now = Date.now()
    if (root.profileBusy || root.buttonProfiles.length <= 1 || now - root.profileLastSwitchAt < 250
        || (!fromWheel && profileWheelLatch.running)) return false
    var index = root.buttonProfiles.findIndex(function(p) { return p.id === root.activeProfileId })
    var result = root.selectProfile(root.buttonProfiles[(index + 1) % root.buttonProfiles.length].id)
    if (result) root.profileLastSwitchAt = now
    return result
  }

  function nextProfileFromWheel() {
    var latched = profileWheelLatch.running
    profileWheelLatch.restart()
    return latched ? false : root.nextProfile(true)
  }

  property Timer profileWheelLatch: Timer {
    interval: 750
    repeat: false
  }

  function setProfileShortcut(value) {
    if (!root.configReadComplete || root.profileBusy || root.sleeping || root.shuttingDown) return false
    var parsed
    try { parsed = Profiles.shortcut(value) }
    catch (_) { root.profileError = "profile_invalid_shortcut"; return false }
    var text = parsed ? parsed.keys : ""
    if (text === root.profileShortcut) return true
    root.storeActiveProfile()
    root.profileTransaction = {fromId: root.activeProfileId, toId: root.activeProfileId,
      fromShortcut: root.profileShortcut, toShortcut: text, removeId: "", rollback: false}
    root.profileError = ""
    root.profileRetryId = ""
    root.profileRetryRemoveId = ""
    root.applyAllSettings()
    return true
  }

  function setProfileSwitchForAll(btnKey) {
    if (!root.configReadComplete || root.profileBusy || Profiles.keys.indexOf(btnKey) < 0) return
    root.storeActiveProfile()
    root.buttonProfiles = root.buttonProfiles.map(function(item) {
      var result = Profiles.copy(item)
      result.buttons[btnKey] = "profile_next"
      return result
    })
    root.loadButtonProfile(Profiles.find(root.buttonProfiles, root.activeProfileId))
    root.applyAllSettings()
    saveDebounce.restart()
  }

  function finishProfileApply(ok, error) {
    var tx = root.profileTransaction
    if (!tx) return
    if (ok) {
      if (!tx.rollback) {
        root.activeProfileId = tx.toId
        root.profileShortcut = tx.toShortcut
        if (tx.removeId) root.buttonProfiles = root.buttonProfiles.filter(function(p) { return p.id !== tx.removeId })
        root.loadButtonProfile(Profiles.find(root.buttonProfiles, root.activeProfileId))
      } else root.profileError = root.profileError === "profile_shortcut_conflict"
        ? "profile_shortcut_conflict" : "profile_switch_restored"
      root.profileTransaction = null
      saveDebounce.restart()
    } else if (!tx.rollback) {
      root.profileError = error === "shortcut_conflict" ? "profile_shortcut_conflict" : "profile_switch_failed"
      root.profileRetryId = tx.toId !== tx.fromId ? tx.toId : ""
      root.profileRetryRemoveId = tx.removeId
      root.profileTransaction = Object.assign({}, tx, {rollback: true})
      root.applyAllSettings()
    } else {
      root.profileTransaction = null
      root.profileError = "profile_rollback_failed"
      root.settingsRecoveryFailed = true
    }
  }

  property var telemetry: ({})
  property string telemetryError: ""
  readonly property string deviceName: "LAMZU THORN"
  readonly property bool connected: telemetry.connected === true
  readonly property bool connectionUnknown: telemetry.connected === null || telemetry.connected === undefined
  readonly property string transport: telemetry.transport || ""
  readonly property var batteryPercent: telemetry.battery === undefined ? null : telemetry.battery
  readonly property int dpi: telemetry.dpi || 0
  readonly property bool isCharging: telemetry.charging === true
  readonly property string macAddress: telemetry.product ? "3554:" + telemetry.product : ""
  readonly property string transportText: connected ? root.t(transport === "usb" ? "transport_usb" : "transport_wireless") : root.t("disconnected")
  readonly property string connectionStatusText: connectionUnknown ? root.t("status_waiting") : transportText
  readonly property string batteryLevelText: batteryPercent === null ? root.t("battery_unknown") : String(batteryPercent) + "%"
  readonly property string batteryReportText: ""
  readonly property string batterySourceDifference: ""
  readonly property string batteryIcon: isCharging ? "󰂄" : "󰁹"
  readonly property string telemetryHelper: decodeURIComponent(Qt.resolvedUrl("scripts/telemetry.py").toString().replace(/^file:\/\//, ""))

  function refreshTelemetry() {
    if (!root.sleeping && !root.shuttingDown && !telemetryProcess.running) telemetryProcess.running = true
  }
  property Process telemetryProcess: Process {
    command: ["/usr/bin/python3", "-I", root.telemetryHelper]
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.telemetry = ({})
        root.telemetryError = "LAMZU status request failed"
      }
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          if (text.length > 4096) throw new Error("Oversized telemetry")
          var result = JSON.parse(text)
          root.telemetry = result
          root.telemetryError = result.error || ""
        } catch (_) {
          root.telemetry = ({})
          root.telemetryError = "Unable to read LAMZU status"
        }
      }
    }
  }
  property Timer telemetryTimer: Timer {
    interval: root.panelOpen || root.connectionUnknown ? 10000 : 60000
    running: !root.sleeping
    repeat: true
    onTriggered: root.refreshTelemetry()
  }

  function t(key) {
    return I18n.t(key, root.effectiveLanguage)
  }

  // Pointer setting updaters
  function setSensitivity(val) {
    var clamped = Math.max(-1.0, Math.min(1.0, Number(val)))
    if (Math.abs(root.sensitivity - clamped) > 0.01) {
      root.sensitivity = clamped
      applyDebounce.restart()
      saveDebounce.restart()
    }
  }

  function setAccelProfile(profile) {
    var p = (profile === "flat" || profile === "adaptive") ? profile : "adaptive"
    if (root.accelProfile !== p) {
      root.accelProfile = p
      applyAccelProfile()
      saveDebounce.restart()
    }
  }

  function setNaturalScroll(enabled) {
    var b = !!enabled
    if (root.naturalScroll !== b) {
      root.naturalScroll = b
      applyNaturalScroll()
      saveDebounce.restart()
    }
  }

  // Button mapping actions catalog
  readonly property var availableActions: [
    "default",
    "profile_next",
    "workspace_next",
    "workspace_prev",
    "window_close",
    "window_float",
    "window_fullscreen",
    "window_next",
    "overview",
    "screenshot",
    "media_play_pause",
    "media_next",
    "media_prev",
    "mute",
    "tab_next",
    "tab_prev",
    "browser_back",
    "browser_forward"
  ]

  function getButtonAction(btnKey) {
    if (btnKey === "back") return root.buttonBack
    if (btnKey === "forward") return root.buttonForward
    if (btnKey === "middle") return root.buttonMiddle
    if (btnKey === "tiltLeft") return root.buttonTiltLeft
    if (btnKey === "tiltRight") return root.buttonTiltRight
    return "default"
  }

  function getCustomShortcut(btnKey) {
    if (btnKey === "back") return root.buttonCustomShortcutBack
    if (btnKey === "forward") return root.buttonCustomShortcutForward
    if (btnKey === "middle") return root.buttonCustomShortcutMiddle
    if (btnKey === "tiltLeft") return root.buttonCustomShortcutTiltLeft
    if (btnKey === "tiltRight") return root.buttonCustomShortcutTiltRight
    return ""
  }

  function getCustomCommand(btnKey) {
    if (btnKey === "back") return root.buttonCustomCmdBack
    if (btnKey === "forward") return root.buttonCustomCmdForward
    if (btnKey === "middle") return root.buttonCustomCmdMiddle
    if (btnKey === "tiltLeft") return root.buttonCustomCmdTiltLeft
    if (btnKey === "tiltRight") return root.buttonCustomCmdTiltRight
    return ""
  }

  function setButtonAction(btnKey, action) {
    if (root.profileBusy || !root.configReadComplete) return
    var act = String(action || "default")
    if (root.availableActions.indexOf(act) < 0 && act !== "custom_shortcut" && act !== "custom_command") return
    if (btnKey === "back") root.buttonBack = act
    else if (btnKey === "forward") root.buttonForward = act
    else if (btnKey === "middle") root.buttonMiddle = act
    else if (btnKey === "tiltLeft") root.buttonTiltLeft = act
    else if (btnKey === "tiltRight") root.buttonTiltRight = act
    root.storeActiveProfile()
    applyButtonBind(btnKey, act)
    saveDebounce.restart()
  }

  function setCustomShortcut(btnKey, shortcutStr) {
    if (root.profileBusy || !root.configReadComplete) return
    var s = String(shortcutStr || "").trim()
    if (s.length > 256 || s.indexOf("\u0000") >= 0) return
    if (btnKey === "back") root.buttonCustomShortcutBack = s
    else if (btnKey === "forward") root.buttonCustomShortcutForward = s
    else if (btnKey === "middle") root.buttonCustomShortcutMiddle = s
    else if (btnKey === "tiltLeft") root.buttonCustomShortcutTiltLeft = s
    else if (btnKey === "tiltRight") root.buttonCustomShortcutTiltRight = s
    setButtonAction(btnKey, "custom_shortcut")
  }

  function setCustomCommand(btnKey, cmdStr) {
    if (root.profileBusy || !root.configReadComplete) return
    var c = String(cmdStr || "").trim()
    if (c.length > 2048 || c.indexOf("\u0000") >= 0) return
    if (btnKey === "back") root.buttonCustomCmdBack = c
    else if (btnKey === "forward") root.buttonCustomCmdForward = c
    else if (btnKey === "middle") root.buttonCustomCmdMiddle = c
    else if (btnKey === "tiltLeft") root.buttonCustomCmdTiltLeft = c
    else if (btnKey === "tiltRight") root.buttonCustomCmdTiltRight = c
    setButtonAction(btnKey, "custom_command")
  }

  function resetButtonToDefault(btnKey) {
    if (root.profileBusy || !root.configReadComplete) return
    if (btnKey === "back") {
      root.buttonBack = "default"
      root.buttonCustomShortcutBack = ""
      root.buttonCustomCmdBack = ""
    } else if (btnKey === "forward") {
      root.buttonForward = "default"
      root.buttonCustomShortcutForward = ""
      root.buttonCustomCmdForward = ""
    } else if (btnKey === "middle") {
      root.buttonMiddle = "default"
      root.buttonCustomShortcutMiddle = ""
      root.buttonCustomCmdMiddle = ""
    } else if (btnKey === "tiltLeft") {
      root.buttonTiltLeft = "default"
      root.buttonCustomShortcutTiltLeft = ""
      root.buttonCustomCmdTiltLeft = ""
    } else if (btnKey === "tiltRight") {
      root.buttonTiltRight = "default"
      root.buttonCustomShortcutTiltRight = ""
      root.buttonCustomCmdTiltRight = ""
    }
    root.storeActiveProfile()
    applyButtonBind(btnKey, "default")
    saveDebounce.restart()
  }

  function actionLabel(action, btnKey) {
    if (action === "custom_shortcut") {
      let s = getCustomShortcut(btnKey)
      return s !== "" ? s : I18n.t("tab_shortcut", root.effectiveLanguage)
    }
    if (action === "custom_command") {
      let c = getCustomCommand(btnKey)
      return c !== "" ? c : I18n.t("tab_command", root.effectiveLanguage)
    }
    return I18n.t("action_" + action, root.effectiveLanguage)
  }

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
  }

  // Convert human-readable key combination ("CTRL + SHIFT + T", "SUPER + 8", "Super P+8") to wtype shell command
  function shortcutToWtype(shortcutStr) {
    if (!shortcutStr) return ""
    var raw = String(shortcutStr).replace(/,/g, " ").replace(/\+/g, " ")
    var tokens = raw.trim().split(/\s+/)
    if (tokens.length === 0 || !raw.trim()) return ""
    var mods = []
    var releaseMods = []
    var keys = []
    for (let i = 0; i < tokens.length; i++) {
      let t = tokens[i].toUpperCase()
      if (t === "CTRL" || t === "CONTROL") {
        mods.push("-M ctrl")
        releaseMods.unshift("-m ctrl")
      } else if (t === "SHIFT") {
        mods.push("-M shift")
        releaseMods.unshift("-m shift")
      } else if (t === "ALT") {
        mods.push("-M alt")
        releaseMods.unshift("-m alt")
      } else if (t === "SUPER" || t === "WIN" || t === "LOGO" || t === "META") {
        mods.push("-M logo")
        releaseMods.unshift("-m logo")
      } else {
        keys.push(tokens[i])
      }
    }
    if (keys.length === 0) return ""
    var cmd = "wtype -s 25 -d 20"
    for (let m = 0; m < mods.length; m++) cmd += " " + mods[m]
    for (let k = 0; k < keys.length; k++) {
      let key = keys[k]
      let uKey = key.toUpperCase()
      if (key.length === 1) {
        cmd += " -k " + shellQuote(key.toLowerCase())
      } else if (uKey === "SPACE") {
        cmd += " -k space"
      } else if (uKey === "ENTER" || uKey === "RETURN") {
        cmd += " -k Return"
      } else if (uKey === "TAB") {
        cmd += " -k Tab"
      } else if (uKey === "ESCAPE" || uKey === "ESC") {
        cmd += " -k Escape"
      } else if (uKey === "BACKSPACE") {
        cmd += " -k BackSpace"
      } else if (uKey === "DELETE" || uKey === "DEL") {
        cmd += " -k Delete"
      } else if (uKey === "INSERT" || uKey === "INS") {
        cmd += " -k Insert"
      } else if (uKey === "HOME") {
        cmd += " -k Home"
      } else if (uKey === "END") {
        cmd += " -k End"
      } else if (uKey === "PAGEUP" || uKey === "PGUP" || uKey === "PAGE_UP" || uKey === "PRIOR") {
        cmd += " -k Prior"
      } else if (uKey === "PAGEDOWN" || uKey === "PGDN" || uKey === "PAGE_DOWN" || uKey === "NEXT") {
        cmd += " -k Next"
      } else if (uKey === "LEFT") {
        cmd += " -k Left"
      } else if (uKey === "RIGHT") {
        cmd += " -k Right"
      } else if (uKey === "UP") {
        cmd += " -k Up"
      } else if (uKey === "DOWN") {
        cmd += " -k Down"
      } else if (uKey === "PRINT" || uKey === "PRINTSCREEN") {
        cmd += " -k Print"
      } else if (uKey === "PAUSE") {
        cmd += " -k Pause"
      } else if (uKey === "MENU") {
        cmd += " -k Menu"
      } else {
        cmd += " -k " + shellQuote(key)
      }
    }
    for (let r = 0; r < releaseMods.length; r++) cmd += " " + releaseMods[r]
    return cmd
  }

  // Debounced slider applicator
  property Timer applyDebounce: Timer {
    interval: 250
    repeat: false
    onTriggered: root.applySensitivity()
  }

  // Debounced config writer
  property Timer saveDebounce: Timer {
    interval: 500
    repeat: false
    onTriggered: root.saveConfig()
  }

  // All callers share one verified application path.
  function applySensitivity() { applyAllSettings() }
  function applyAccelProfile() { applyAllSettings() }
  function applyNaturalScroll() { applyAllSettings() }

  function buildBindSnippet(code, action, btnKey, buttonProfile) {
    var lua = "pcall(function() hl.unbind(\"" + code + "\") end)\n"
    if (action === "default") {
      return lua
    } else if (action === "profile_next") {
      let axis = code === "mouse_left" || code === "mouse_right"
      let command = "omarchy-shell slovn.lamzu " + (axis ? "nextProfileFromWheel" : "nextProfile")
      lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Next Profile\", " + JSON.stringify(command)
        + ", { release = " + (axis ? "false" : "true") + " })\n"
    } else if (action === "workspace_next") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Next Workspace\", hl.dsp.focus({ workspace = \"e+1\" }))\n"
    } else if (action === "workspace_prev") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Prev Workspace\", hl.dsp.focus({ workspace = \"e-1\" }))\n"
    } else if (action === "window_close") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Close Window\", hl.dsp.window.close())\n"
    } else if (action === "window_float") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Toggle Floating\", hl.dsp.window.float({ action = \"toggle\" }))\n"
    } else if (action === "window_fullscreen") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Fullscreen\", hl.dsp.window.fullscreen({ mode = \"fullscreen\" }))\n"
    } else if (action === "window_next") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Next Window\", hl.dsp.window.cycle_next())\n"
    } else if (action === "overview") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Overview\", \"omarchy-shell moorgrove.overview toggle\")\n"
    } else if (action === "screenshot") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Screenshot\", \"omarchy-capture-screenshot\")\n"
    } else if (action === "media_play_pause") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Play/Pause\", \"playerctl play-pause\")\n"
    } else if (action === "media_next") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Next Track\", \"playerctl next\")\n"
    } else if (action === "media_prev") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Prev Track\", \"playerctl previous\")\n"
    } else if (action === "mute") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Toggle Mute\", \"wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle\")\n"
    } else if (action === "tab_next") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Next Tab\", \"wtype -M ctrl -k Tab\")\n"
    } else if (action === "tab_prev") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Prev Tab\", \"wtype -M ctrl -M shift -k Tab\")\n"
    } else if (action === "browser_back") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Browser Back\", \"wtype -M alt -k Left\")\n"
    } else if (action === "browser_forward") {
      lua += "o.bind(\"" + code + "\", \"LAMZU THORN: Browser Forward\", \"wtype -M alt -k Right\")\n"
    } else if (action === "custom_shortcut") {
      let sc = buttonProfile ? buttonProfile.customShortcuts[btnKey] : getCustomShortcut(btnKey)
      if (sc !== "") {
        let norm = sc.toUpperCase().replace(/,/g, " ").replace(/\+/g, " ").trim().replace(/\s+/g, " ")
        let wsMatch = norm.match(/^(SUPER|WIN|LOGO)\s+([0-9]+)$/)
        if (wsMatch) {
          lua += "o.bind(" + JSON.stringify(code) + ", " + JSON.stringify("LAMZU THORN: Workspace " + wsMatch[2]) + ", hl.dsp.focus({ workspace = \"" + wsMatch[2] + "\" }))\n"
        } else if (norm === "SUPER CTRL TAB" || norm === "SUPER CONTROL TAB" || norm === "WIN CTRL TAB" || norm === "WIN CONTROL TAB") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Former Workspace\", hl.dsp.focus({ workspace = \"previous\" }))\n"
        } else if (norm === "SUPER SHIFT TAB" || norm === "WIN SHIFT TAB") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Prev Workspace\", hl.dsp.focus({ workspace = \"e-1\" }))\n"
        } else if (norm === "SUPER TAB" || norm === "WIN TAB") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Next Workspace\", hl.dsp.focus({ workspace = \"e+1\" }))\n"
        } else if (norm === "SUPER W" || norm === "SUPER Q" || norm === "WIN W" || norm === "WIN Q") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Close Window\", hl.dsp.window.close())\n"
        } else if (norm === "SUPER F" || norm === "WIN F") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Fullscreen\", hl.dsp.window.fullscreen({ mode = \"fullscreen\" }))\n"
        } else if (norm === "SUPER T" || norm === "WIN T") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Toggle Float\", hl.dsp.window.float({ action = \"toggle\" }))\n"
        } else if (norm === "SUPER SPACE" || norm === "WIN SPACE") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Menu\", \"omarchy-menu toggle\")\n"
        } else if (norm === "SUPER S" || norm === "WIN S") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Scratchpad\", hl.dsp.workspace.toggle_special(\"scratchpad\"))\n"
        } else if (norm === "SUPER LEFT" || norm === "WIN LEFT") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Focus Left\", hl.dsp.focus({ direction = \"l\" }))\n"
        } else if (norm === "SUPER RIGHT" || norm === "WIN RIGHT") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Focus Right\", hl.dsp.focus({ direction = \"r\" }))\n"
        } else if (norm === "SUPER UP" || norm === "WIN UP") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Focus Up\", hl.dsp.focus({ direction = \"u\" }))\n"
        } else if (norm === "SUPER DOWN" || norm === "WIN DOWN") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Focus Down\", hl.dsp.focus({ direction = \"d\" }))\n"
        } else if (norm === "INSERT" || norm === "INS") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Voxtype Dictation\", \"voxtype record toggle\")\n"
        } else if (norm === "SUPER INSERT" || norm === "WIN INSERT") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Voice Agent\", \"omarchy-voice-agent toggle || omarchy-voice-agent start\")\n"
        } else if (norm === "SUPER ALT A" || norm === "WIN ALT A") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: TTS Clipboard\", " + JSON.stringify(shellQuote(root.configHome + "/omarchy/plugins/io.github.hikari112.tts/bin/speak") + " --clipboard") + ")\n"
        } else if (norm === "SUPER ALT E" || norm === "WIN ALT E") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: TTS Selection\", " + JSON.stringify(shellQuote(root.configHome + "/omarchy/plugins/io.github.hikari112.tts/bin/speak") + " --toggle") + ")\n"
        } else if (norm === "SUPER ALT X" || norm === "WIN ALT X") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: TTS Stop\", " + JSON.stringify(shellQuote(root.configHome + "/omarchy/plugins/io.github.hikari112.tts/bin/speak") + " --stop") + ")\n"
        } else if (norm === "SUPER ALT R" || norm === "WIN ALT R") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: TTS Snip\", " + JSON.stringify(shellQuote(root.configHome + "/omarchy/plugins/io.github.hikari112.tts/bin/speak") + " --snip") + ")\n"
        } else {
          let wcmd = shortcutToWtype(sc)
          if (wcmd !== "") {
            lua += "o.bind(" + JSON.stringify(code) + ", " + JSON.stringify("LAMZU THORN: " + sc) + ", " + JSON.stringify(wcmd) + ")\n"
          }
        }
      }
    } else if (action === "custom_command") {
      let rawCmd = buttonProfile ? buttonProfile.customCommands[btnKey] : getCustomCommand(btnKey)
      if (rawCmd !== "") {
        lua += "o.bind(" + JSON.stringify(code) + ", \"LAMZU THORN: Command\", " + JSON.stringify(rawCmd) + ")\n"
      }
    }
    return lua
  }

  function applyButtonBind(btnKey, action) { applyAllSettings() }

  function suflyorHold(code, action, key, profile) {
    if (action !== "custom_shortcut") return null
    var shortcut = profile ? profile.customShortcuts[key] : getCustomShortcut(key)
    var parsed
    try { parsed = Profiles.shortcut(shortcut) } catch (_) { return null }
    if (!parsed || parsed.key !== "F9" || (parsed.modmask !== 64 && parsed.modmask !== 65)) return null
    // Suflyor's native PTT protocol needs both edges of the physical button.
    // Sending a complete synthetic key chord cannot preserve the hold duration.
    var mode = parsed.modmask === 64 ? "mic" : "sys"
    var description = "LAMZU THORN: Suflyor PTT " + mode
    var executable = Quickshell.env("HOME") + "/.local/lib/suflyor-omarchy/suflyord"
    var command = "env XDG_CONFIG_HOME=" + shellQuote(root.configHome) + " " + shellQuote(executable) + " --command ptt-" + mode
    var lua = ""
    for (let release of [false, true]) {
      lua += "o.bind(" + JSON.stringify(code) + ", " + JSON.stringify(description) + ", "
        + JSON.stringify(command + (release ? "-up" : "-down"))
        + ", { release = " + (release ? "true" : "false") + ", ignore_mods = true })\n"
    }
    return {lua: lua, expected: {description: description, hold: true}}
  }

  function buildSettingsRequest() {
    var tx = root.profileTransaction
    var selected = tx ? Profiles.find(root.buttonProfiles, tx.rollback ? tx.fromId : tx.toId) : null
    var lua = "do\n"
    for (let deviceName of ["compx-lamzu-thorn-1", "compx-lamzu-pro-1k-receiver-1"]) {
      let sensitivity = Number(root.sensitivity)
      if (!isFinite(sensitivity)) throw new Error("Invalid sensitivity")
      let profile = root.accelProfile
      if (profile !== "adaptive" && profile !== "flat") throw new Error("Invalid acceleration profile")
      lua += "hl.device({ name = " + JSON.stringify(deviceName)
        + ", sensitivity = " + Math.max(-1, Math.min(1, sensitivity)).toFixed(2)
        + ", accel_profile = " + JSON.stringify(profile)
        + ", natural_scroll = " + (root.naturalScroll ? "true" : "false") + " })\n"
    }
    var buttons = { "mouse:275": "back", "mouse:276": "forward", "mouse:274": "middle" }
    var expected = {}
    for (let code in buttons) {
      let key = buttons[code]
      let action = selected ? selected.buttons[key] : getButtonAction(key)
      let hold = suflyorHold(code, action, key, selected)
      if (hold) {
        expected[code] = hold.expected
        lua += hold.lua
        continue
      }
      let snippet = buildBindSnippet(code, action, key, selected)
      // Read the description from the same generated bind, including JSON escapes.
      let match = snippet.match(/o\.bind\([^,]+,\s*("(?:\\.|[^"\\])*")/)
      expected[code] = match ? JSON.parse(match[1]) : null
      if (action === "profile_next") expected[code] = {description: expected[code], release: code !== "mouse_left" && code !== "mouse_right",
        dispatcher: "__lua"}
      lua += snippet
    }
    var shortcut = tx ? (tx.rollback ? tx.fromShortcut : tx.toShortcut) : root.profileShortcut
    return { lua: lua + "end\n", expected: expected, profileShortcut: Profiles.shortcut(shortcut) }
  }

  property var pendingSettingsRequest: null
  property bool settingsApplying: false
  property bool settingsRecoveryFailed: false
  property bool settingsStopping: false
  property int settingsGeneration: 0
  property int settingsCapturedGeneration: -1
  property int settingsVerifiedGeneration: -1
  readonly property bool settingsPending: applyDebounce.running || settingsApplying || pendingSettingsRequest !== null
  readonly property bool settingsVerified: settingsConfigured && settingsVerifiedGeneration === settingsGeneration
    && !settingsPending && !settingsRecoveryFailed
  property var settingsCapturedProfileTransaction: null
  property int settingsExitCode: -1
  property string settingsOutput: ""
  readonly property string settingsHelper: decodeURIComponent(Qt.resolvedUrl("scripts/apply-settings.py").toString().replace(/^file:\/\//, ""))

  function applyAllSettings() {
    if (!root.configReadComplete || root.shuttingDown) return
    settingsGeneration++
    try {
      pendingSettingsRequest = buildSettingsRequest()
      root.settingsConfigured = true
      settingsRecoveryFailed = false
      Qt.callLater(drainSettingsRequest)
    } catch (_) {
      pendingSettingsRequest = null
      settingsRecoveryFailed = true
      console.warn("LAMZU THORN: invalid settings; application skipped")
      if (root.profileBusy) root.finishProfileApply(false, "")
    }
  }

  function drainSettingsRequest() {
    if (root.sleeping || root.shuttingDown || settingsApplying || settingsApplier.running || pendingSettingsRequest === null) return
    settingsApplying = true
    settingsCapturedGeneration = settingsGeneration
    root.settingsCapturedProfileTransaction = root.profileTransaction
    settingsStopping = false
    settingsExitCode = -1
    settingsOutput = ""
    settingsApplier.command = ["/usr/bin/python3", "-I", root.settingsHelper, JSON.stringify(pendingSettingsRequest)]
    pendingSettingsRequest = null
    // Three attempts can each read conflicts, apply Lua, and read back (3 x 5s),
    // plus 2/4s retry delays. Leave room for the complete bounded helper budget.
    settingsDeadline.interval = 60000
    settingsDeadline.restart()
    settingsApplier.running = true
    settingsStartCheck.restart()
  }

  function finishSettingsApply() {
    if (!settingsApplying || settingsApplier.running) return
    settingsStartCheck.stop()
    settingsDeadline.stop()
    var ok = false
    var error = ""
    try {
      let result = JSON.parse(settingsOutput)
      ok = settingsExitCode === 0 && result.ok === true
      error = result.error || ""
    } catch (_) {}
    if (settingsCapturedGeneration === settingsGeneration) {
      settingsRecoveryFailed = !ok
      if (ok) root.settingsVerifiedGeneration = settingsCapturedGeneration
      if (root.settingsCapturedProfileTransaction && root.settingsCapturedProfileTransaction === root.profileTransaction)
        root.finishProfileApply(ok, error)
    }
    settingsApplying = false
    if (ok) console.info("LAMZU THORN: settings applied and button bindings verified")
    else console.warn("LAMZU THORN: settings verification failed after bounded recovery")
    Qt.callLater(drainSettingsRequest)
  }

  property Process settingsApplier: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.settingsOutput = text.length <= 1024 ? text : ""
    }
    onExited: function(exitCode) {
      root.settingsExitCode = exitCode
      Qt.callLater(root.finishSettingsApply)
    }
    onRunningChanged: {
      if (!running && root.settingsApplying) Qt.callLater(root.finishSettingsApply)
    }
  }
  property Timer settingsStartCheck: Timer {
    interval: 1000
    onTriggered: root.finishSettingsApply()
  }
  property Timer settingsDeadline: Timer {
    interval: 60000
    onTriggered: {
      if (settingsApplier.running && settingsApplier.processId > 0) {
        settingsApplier.signal(root.settingsStopping ? 9 : 15)
        root.settingsStopping = true
        interval = 2000
        restart()
      } else root.finishSettingsApply()
    }
  }
  Component.onDestruction: {
    root.shuttingDown = true
    telemetryProcess.running = false
    sleepMonitor.running = false
    settingsApplier.running = false
  }

  // Config persistence (saves to ~/.config/omarchy/lamzu.json via safe discrete argv without shell execution)
  function saveConfig() {
    if (!root.configReadComplete || root.profileBusy || root.configLoadFailed) return
    root.storeActiveProfile()
    var cfg = {
      version: 2,
      sensitivity: root.sensitivity,
      accelProfile: root.accelProfile,
      naturalScroll: root.naturalScroll,
      profiles: root.buttonProfiles,
      activeProfileId: root.activeProfileId,
      profileShortcut: root.profileShortcut
    }
    root.pendingConfig = JSON.stringify(cfg, null, 2)
    drainConfigWrite()
  }

  property string pendingConfig: ""
  function drainConfigWrite() {
    if (root.shuttingDown || root.configWriting || configWriter.running || !root.pendingConfig) return
    configWriter.command = ["/usr/bin/python3", "-I", root.configHelper, "write", root.configPath, root.pendingConfig]
    root.pendingConfig = ""
    root.configWriting = true
    configWriter.running = true
    configWriteStartCheck.restart()
  }
  property Process configWriter: Process {
    onExited: function(exitCode) {
      root.finishConfigWrite(exitCode)
    }
  }

  function finishConfigWrite(exitCode) {
    configWriteStartCheck.stop()
    root.configSaveFailed = exitCode !== 0
    root.configStored = exitCode === 0
    root.configWriting = false
    if (exitCode === 0) root.configLoadFailed = false
    else console.warn("LAMZU THORN: preferences could not be saved")
    Qt.callLater(root.drainConfigWrite)
  }
  function retrySettings() {
    if (root.profileRetryId && !root.profileBusy) {
      root.selectProfile(root.profileRetryId, root.profileRetryRemoveId)
      return
    }
    if (root.configSaveFailed) root.saveConfig()
    if (root.settingsRecoveryFailed) {
      root.profileError = ""
      root.applyAllSettings()
    }
  }
  property Timer configWriteStartCheck: Timer {
    interval: 1000
    onTriggered: if (root.configWriting && !configWriter.running) root.finishConfigWrite(-1)
  }
  property Timer configReadStartCheck: Timer {
    interval: 1000
    onTriggered: {
      if (!configLoader.running && !root.configReadComplete) {
        root.configReadComplete = true
        root.configLoadFailed = true
      }
    }
  }

  // Config loader process (discrete argv, no shell interpreter)
  property Process configLoader: Process {
    command: ["/usr/bin/python3", "-I", root.configHelper, "read", root.configPath]
    onExited: function(exitCode) {
      configReadStartCheck.stop()
      root.configReadComplete = true
      if (exitCode !== 0) root.configLoadFailed = true
      if (exitCode !== 0) console.warn("LAMZU THORN: invalid or unreadable preferences; using defaults without applying them")
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.configReadComplete = true
        var txt = (text || "").trim()
        if (!txt) return
        try {
          let cfg = JSON.parse(txt)
          if (!cfg) return // First install: do not overwrite existing compositor bindings.
          if (typeof cfg.sensitivity === "number") root.sensitivity = cfg.sensitivity
          if (typeof cfg.accelProfile === "string") root.accelProfile = cfg.accelProfile
          if (typeof cfg.naturalScroll === "boolean") root.naturalScroll = cfg.naturalScroll
          root.loadProfileConfig(cfg)
          root.configStored = true
          root.applyAllSettings()
        } catch (e) {
          root.configLoadFailed = true
        }
      }
    }
  }

  // System sleep/resume monitor (logind PrepareForSleep signal listener)
  property Process sleepMonitor: Process {
    command: [
      "/usr/bin/dbus-monitor", "--system",
      "type='signal',sender='org.freedesktop.login1',path='/org/freedesktop/login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'"
    ]
    onExited: root.scheduleSleepMonitorRetry()
    stdout: SplitParser {
      onRead: function(line) {
        // The selected logind signal has one bounded boolean argument.
        var value = String(line).trim()
        if (value === "boolean true") root.prepareForSleep(true)
        else if (value === "boolean false") root.prepareForSleep(false)
      }
    }
  }

  function prepareForSleep(asleep) {
    root.sleeping = asleep
    if (asleep) {
      telemetryProcess.running = false
      if (settingsApplier.running) settingsApplier.signal(15)
    } else {
      root.sleepMonitorRestarts = 0
      root.sleepMonitorFailed = false
      root.refreshTelemetry()
      if (root.settingsConfigured) root.applyAllSettings()
    }
  }
  function scheduleSleepMonitorRetry() {
    if (root.shuttingDown) return
    root.sleepMonitorFailed = true
    if (root.sleepMonitorRestarts < 3) sleepRetry.restart()
  }
  property Timer sleepRetry: Timer {
    interval: 2000
    onTriggered: {
      if (root.shuttingDown || sleepMonitor.running) return
      root.sleepMonitorRestarts++
      sleepMonitor.running = true
      sleepStartCheck.restart()
    }
  }
  property Timer sleepStartCheck: Timer {
    interval: 1000
    onTriggered: {
      if (!sleepMonitor.running) root.scheduleSleepMonitorRetry()
      else root.sleepMonitorFailed = false
    }
  }

  Component.onCompleted: {
    root.loadProfileConfig(null)
    configLoader.running = true
    configReadStartCheck.restart()
    root.refreshTelemetry()
    sleepMonitor.running = true
    sleepStartCheck.restart()
  }
}
