import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Services.UPower
import "I18n.js" as I18n
import "Battery.js" as Battery
import "ButtonProfiles.js" as Profiles

// Single state owner for Logitech MX Ergo trackball.
// Reactive BlueZ/UPower telemetry and Hyprland pointer/button controls.
QtObject {
  id: root

  property string targetAddress: ""
  property string hyprDeviceName: "logitech-mx-ergo-multi-device-trackball-"
  property string language: "system"
  readonly property string effectiveLanguage: I18n.resolveLanguage(language, Qt.locale().name)

  signal localeRequested(string code)

  function setLocale(code) {
    if (["system", "en", "ru", "de", "fr", "es", "it", "pt", "zh", "ja", "ko"].indexOf(code) < 0) return
    root.language = code
    root.localeRequested(code)
  }

  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  readonly property string configPath: configHome + "/omarchy/mx-ergo.json"
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
        console.info("MX Ergo: restoring settings after Hyprland reload")
        root.applyAllSettings()
      }
    }
  }

  // Refresh optional controller diagnostics when the panel opens
  property bool panelOpen: false
  onPanelOpenChanged: {
    if (root.panelOpen) {
      root.checkLowLatency()
    }
  }

  property string lowLatencyState: "unknown"
  property bool lowLatencyHelperAvailable: false
  property bool lowLatencyCanRestore: false
  property bool lowLatencyLegacy: false
  property bool lowLatencyConfigured: false
  property bool lowLatencyFailed: false
  readonly property bool lowLatencyEnabled: lowLatencyState === "applied"
  readonly property bool lowLatencyBusy: lowLatencyApply.running
  readonly property string bluetoothAdapter: btDevice && btDevice.adapter
    ? String(btDevice.adapter.adapterId).split("/").pop() : ""
  readonly property string lowLatencyScript: decodeURIComponent(Qt.resolvedUrl("scripts/low-latency.sh").toString().replace(/^file:\/\//, ""))
  onBluetoothAdapterChanged: root.checkLowLatency()

  // Auto-reconnect on system wake / recovery
  property bool autoReconnect: true
  property bool startupRecoveryAttempted: false
  property var startupRecoveryDevice: null
  property var wakeRetryDevice: null
  property bool isConnecting: false
  property string recoveryStage: ""
  property string recoveryResult: ""
  property var recoveryDevice: null
  property var recoveryAdapter: null
  property string recoveryTargetAddress: ""
  property bool recoveryScanStarted: false
  property bool recoverySeenTarget: false
  property string recoveryOtherAddress: ""
  property bool recoveryOtherMultiple: false
  property var recoveryOtherPaired: null
  property var recoveryOtherBonded: null
  property bool recoveryStopping: false
  property bool recoveryCleanupEscalated: false
  property string recoveryAbortResult: ""
  property double recoveryStartedAt: 0
  readonly property bool recoveryBusy: recoveryStage !== "" || recoveryStopping
  readonly property string recoveryScanNote: recoveryResult !== "" && recoveryScanStarted
    ? root.t(recoverySeenTarget ? "recovery_target_seen" : "recovery_target_not_seen") : ""
  readonly property string recoveryOtherNote: {
    if (recoveryResult === "" || recoveryOtherAddress === "") return ""
    if (recoveryOtherMultiple) return root.t("recovery_other_multiple")
    function flag(value) {
      return root.t(value === null ? "battery_unknown" : (value ? "state_yes" : "state_no"))
    }
    return root.t("recovery_other_seen") + " " + recoveryOtherAddress + " ("
      + "Paired=" + flag(recoveryOtherPaired) + ", "
      + "Bonded=" + flag(recoveryOtherBonded) + ")"
  }

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

  // Reactive devices from native C++ services
  readonly property var btAdaptersList: Bluetooth.adapters ? Bluetooth.adapters.values : []
  readonly property var btDevicesList: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var upDevicesList: UPower.devices ? UPower.devices.values : []
  property string observedBtAddress: ""

  // Matched Bluetooth device
  readonly property var btDevice: {
    var list = btDevicesList
    var target = root.targetAddress.toUpperCase().replace(/:/g, "")
    var matches = []
    for (let i = 0; i < list.length; i++) {
      let d = list[i]
      if (!d) continue
      let addr = String(d.address || "").toUpperCase().replace(/:/g, "")
      let name = String(d.name || d.deviceName || "")
      if ((target !== "" && addr === target) || (target === "" && name.indexOf("MX Ergo") !== -1)) {
        matches.push(d)
      }
    }
    if (matches.length === 1) return matches[0]
    if (target !== "") return null
    var connected = matches.filter(function(device) {
      return device.connected && device.paired && device.bonded
    })
    if (connected.length === 1) return connected[0]
    var bonded = matches.filter(function(device) { return device.paired && device.bonded })
    if (bonded.length === 1) return bonded[0]
    if (connected.length > 1 || root.observedBtAddress === "") return null
    var previous = matches.filter(function(device) {
      return String(device.address || "").toUpperCase() === root.observedBtAddress
    })
    return previous.length === 1 ? previous[0] : null
  }

  property var powerCandidates: []
  property Instantiator powerDevices: Instantiator {
    model: root.upDevicesList
    delegate: PowerDevice {
      required property var modelData
      device: modelData
    }
    onObjectAdded: function(index, object) {
      root.powerCandidates = root.powerCandidates.concat([object])
    }
    onObjectRemoved: function(index, object) {
      root.powerCandidates = root.powerCandidates.filter(function(item) { return item !== object })
    }
  }

  // Reject ambiguous/foreign devices instead of selecting the first Logitech battery.
  readonly property var matchedPower: {
    var target = root.btDevice ? root.btDevice.address : root.targetAddress
    var available = root.powerCandidates.filter(function(item) {
      return item.device && item.device.ready && item.device.isPresent && item.identity
        && (item.identity.transport !== "ble" || root.bleLinked)
    })
    var matches = available.filter(function(item) { return Battery.matches(item.identity, target) })
    if (matches.length === 1) return matches[0]
    if (matches.length > 1 || root.bleLinked) return null
    // Bluetooth MAC and receiver serial differ. With no active BLE link, a
    // single receiver-side MX Ergo can be selected by its verified product ID.
    var receivers = available.filter(function(item) { return item.identity.transport === "unifying" })
    return receivers.length === 1 ? receivers[0] : null
  }
  readonly property var upDevice: matchedPower ? matchedPower.device : null
  // Connection status reports the BlueZ link. Pairing validity is shown
  // separately and remains a prerequisite for recovery of a saved bond.
  readonly property bool bleLinked: !!btDevice && !!btDevice.connected

  readonly property string transport: {
    if (bleLinked) return "ble"
    // A cached BLE battery is not evidence of a receiver connection.
    if (matchedPower && matchedPower.identity.transport === "unifying") return "unifying"
    return ""
  }

  readonly property bool connected: transport !== ""
  readonly property bool deviceFound: btDevice !== null || matchedPower !== null
  readonly property string connectionStatusText: {
    if (root.targetAddress !== "" && !root.btDevice) return root.t("status_record_missing")
    if (root.btDevice && root.btDevice.connected && (!root.btDevice.paired || !root.btDevice.bonded))
      return root.t("status_pairing_incomplete")
    if (root.transport === "unifying") return root.transportText
    if (root.bleLinked) return root.t("status_link_reported")
    if (root.btDevice && root.btDevice.paired && root.btDevice.bonded)
      return root.t("status_bonded_disconnected")
    if (root.btDevice) return root.t("status_pairing_required")
    return root.t("status_selection_unavailable")
  }
  function logConnectionState() {
    var device = root.btDevice
    console.info("MX Ergo: selected=" + (device ? String(device.address) : "none")
      + " target=" + (root.targetAddress || "auto")
      + " BlueZ connected=" + (device ? device.connected : "unknown")
      + " paired=" + (device ? device.paired : "unknown")
      + " bonded=" + (device ? device.bonded : "unknown")
      + " transport=" + (root.transport || "none")
      + " battery=" + (root.batteryTier || "unknown"))
  }
  onConnectionStatusTextChanged: Qt.callLater(root.logConnectionState)
  onBatteryTierChanged: Qt.callLater(root.logConnectionState)
  readonly property var isCharging: !connected || !upDevice || upDevice.state === UPowerDeviceState.Unknown
    ? null : upDevice.state === UPowerDeviceState.Charging

  onConnectedChanged: {
    if (root.connected) {
      root.startupRecoveryAttempted = true
      startupRecoveryTimer.stop()
      root.startupRecoveryDevice = null
      root.isConnecting = false
      connectingResetTimer.stop()
      wakeReconnectTimer.stop()
      wakeStage2Timer.stop()
      wakeRetryDeadline.stop()
      root.wakeRetryDevice = null
    }
  }

  readonly property bool canReconnect: !!root.btDevice
    && /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(root.btDevice.address)
    && !!root.btDevice.paired && !!root.btDevice.bonded
    && !!root.btDevice.adapter && root.btDevice.adapter.enabled
  readonly property bool canRecover: root.canReconnect
    // bluetoothctl selects its own default adapter; only one adapter is safe.
    && root.btAdaptersList.length === 1 && root.btDevice.adapter === root.btAdaptersList[0]
  readonly property bool canStartRecovery: root.canRecover
    && root.btDevice.state !== BluetoothDeviceState.Connecting
    && root.btDevice.state !== BluetoothDeviceState.Disconnecting
  onCanStartRecoveryChanged: root.scheduleStartupRecovery()
  onConfigReadCompleteChanged: root.scheduleStartupRecovery()
  onAutoReconnectChanged: root.scheduleStartupRecovery()

  function scheduleStartupRecovery() {
    if (root.startupRecoveryAttempted || !root.configReadComplete || !root.autoReconnect
        || root.connected || root.sleeping || root.shuttingDown || !root.canStartRecovery) {
      startupRecoveryTimer.stop()
      return
    }
    if (!startupRecoveryTimer.running) {
      root.startupRecoveryDevice = root.btDevice
      startupRecoveryTimer.restart()
    }
  }

  function startStartupRecovery() {
    if (root.startupRecoveryAttempted || root.btDevice !== root.startupRecoveryDevice
        || !root.configReadComplete || !root.autoReconnect
        || root.connected || root.recoveryBusy || root.isConnecting || root.sleeping
        || root.shuttingDown || !root.canStartRecovery) return
    root.recoverDevice(false)
  }

  function reconnectDevice() {
    if (root.connected || root.isConnecting || root.recoveryBusy || root.sleeping || !root.canReconnect
        || root.btDevice.state === BluetoothDeviceState.Connecting) return false

    var target = root.btDevice.address
    // Strict operand validation: must match valid 6-octet MAC address pattern
    if (!/^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(target)) return false

    root.isConnecting = true
    connectingResetTimer.restart()

    root.btDevice.connect()
    return true
  }

  function recoverySelectionValid() {
    return !!root.recoveryDevice && root.btDevice === root.recoveryDevice
      && !!root.recoveryAdapter && root.recoveryDevice.adapter === root.recoveryAdapter
      && root.canRecover && String(root.recoveryDevice.address).toUpperCase() === root.recoveryTargetAddress
  }

  // Explicit, target-only recovery. BlueZ's link report and a fresh discovery
  // report are recorded separately; neither proves that pointer input works.
  function recoverDevice(allowDisconnect) {
    if (!root.canStartRecovery || root.recoveryBusy || recoveryScanProcess.running || recoveryCancelProcess.running
        || root.isConnecting || root.sleeping || root.shuttingDown
        || (allowDisconnect === false && (root.btDevice.connected || root.connected))) return false
    root.startupRecoveryAttempted = true
    startupRecoveryTimer.stop()
    root.startupRecoveryDevice = null
    root.recoveryDevice = root.btDevice
    root.recoveryAdapter = root.btDevice.adapter
    root.recoveryTargetAddress = String(root.btDevice.address).toUpperCase()
    root.recoveryStartedAt = Date.now()
    console.info("MX Ergo recovery: start address=" + root.recoveryTargetAddress
      + " source=" + (allowDisconnect === false ? "startup" : "manual")
      + " BlueZ connected=" + root.recoveryDevice.connected)
    if (root.targetAddress === "") root.observedBtAddress = root.recoveryTargetAddress
    root.recoveryResult = ""
    root.recoveryScanStarted = false
    root.recoverySeenTarget = false
    root.recoveryOtherAddress = ""
    root.recoveryOtherMultiple = false
    root.recoveryOtherPaired = null
    root.recoveryOtherBonded = null
    root.recoveryAbortResult = ""
    wakeReconnectTimer.stop()
    wakeStage2Timer.stop()
    wakeRetryDeadline.stop()
    root.wakeRetryDevice = null
    if (root.recoveryDevice.connected) {
      if (allowDisconnect === false) {
        root.finishRecovery("recovery_link_reported")
        return true
      }
      root.recoveryStage = "disconnecting"
      recoveryStepTimer.interval = 5000
      recoveryStepTimer.restart()
      root.recoveryDevice.disconnect()
    } else {
      root.startRecoveryScan()
    }
    return true
  }

  function cancelRecovery() {
    if (root.recoveryStage === "connecting" && root.recoveryDevice)
      root.abortRecoveryConnect("recovery_cancelled")
    else if (root.recoveryStage !== "" && root.recoveryStage !== "cancellingConnect")
      root.finishRecovery("recovery_cancelled")
  }

  function abortRecoveryConnect(result) {
    if (root.recoveryStage !== "connecting" || !root.recoveryDevice) return
    root.recoveryAbortResult = result
    console.info("MX Ergo recovery: cancelling pending Connect address="
      + root.recoveryTargetAddress + " reason=" + result)
    root.recoveryStage = "cancellingConnect"
    root.recoveryStopping = true
    recoveryStepTimer.interval = 15000
    recoveryStepTimer.restart()
    // BlueZ Device1.Disconnect cancels a pending Connect. Quickshell's
    // disconnect() refuses this call while its Connected flag is false.
    recoveryCancelProcess.command = ["/usr/bin/bluetoothctl", "--timeout", "10",
      "disconnect", root.recoveryTargetAddress]
    recoveryCancelProcess.running = true
    if (recoveryScanProcess.running) recoveryScanProcess.running = false
  }

  function settleRecoveryAbort() {
    if (root.recoveryStage !== "cancellingConnect" || recoveryCancelProcess.running) return
    if (!root.recoveryDevice || root.btDevice !== root.recoveryDevice)
      root.finishRecovery("recovery_cancel_unconfirmed")
    else if (root.recoveryDevice.connected)
      root.finishRecovery("recovery_cancel_unconfirmed")
    else if (root.recoveryDevice.state !== BluetoothDeviceState.Connecting)
      root.finishRecovery(root.recoveryAbortResult)
  }

  function startRecoveryScan() {
    if (!root.recoverySelectionValid()) {
      root.finishRecovery("recovery_unavailable")
      return
    }
    root.recoveryStage = "startingScan"
    console.info("MX Ergo recovery: starting owned LE scan address=" + root.recoveryTargetAddress)
    recoveryStepTimer.interval = 5000
    recoveryStepTimer.restart()
    recoveryScanProcess.running = true
  }

  function beginRecoveryScanWindow() {
    root.recoveryScanStarted = true
    console.info("MX Ergo recovery: owned LE scan started address=" + root.recoveryTargetAddress)
    root.recoveryStage = "scanning"
    recoveryStepTimer.interval = 10000
    recoveryStepTimer.restart()
  }

  function startRecoveryConnect() {
    if (root.recoveryStage !== "scanning") return
    if (!root.recoverySelectionValid()) {
      root.finishRecovery("recovery_unavailable")
      return
    }
    root.recoveryStage = "connecting"
    console.info("MX Ergo recovery: Connect address=" + root.recoveryTargetAddress
      + " freshReport=" + root.recoverySeenTarget)
    recoveryStepTimer.interval = 35000
    recoveryStepTimer.restart()
    if (root.recoveryDevice.connected) root.finishRecovery("recovery_link_reported")
    else root.recoveryDevice.connect()
  }

  function updateRecoveryOtherState() {
    if (root.recoveryOtherAddress === "" || root.recoveryOtherMultiple) return
    var list = root.btDevicesList
    for (let i = 0; i < list.length; i++) {
      let device = list[i]
      if (device && String(device.address || "").toUpperCase() === root.recoveryOtherAddress) {
        root.recoveryOtherPaired = !!device.paired
        root.recoveryOtherBonded = !!device.bonded
        return
      }
    }
  }

  function noteRecoveryOtherAddress(address) {
    if (root.recoveryOtherAddress !== "" && root.recoveryOtherAddress !== address) {
      root.recoveryOtherMultiple = true
      return
    }
    root.recoveryOtherAddress = address
    root.updateRecoveryOtherState()
  }

  function handleRecoveryScanLine(rawLine) {
    if (root.recoveryStage === "") return
    var line = String(rawLine).replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").trim()
    if (root.recoveryStage === "startingScan") {
      if (line.indexOf("Failed to start discovery") !== -1 || line.indexOf("SetDiscoveryFilter failed") !== -1) {
        root.finishRecovery("recovery_scan_start_failed")
        return
      }
      if (line.indexOf("Discovery started") !== -1) root.beginRecoveryScanWindow()
    }
    if (!root.recoveryScanStarted) return

    // Initial cached Device objects are printed before our scan starts. Accept
    // only newly discovered names or fresh advertisement-derived changes.
    var match = line.match(/^\[(NEW|CHG)\] Device ((?:[0-9A-F]{2}:){5}[0-9A-F]{2})\s+(.+)$/i)
    if (!match) return
    var detail = match[3]
    if (match[1].toUpperCase() === "CHG" && !/^(RSSI|TxPower|AdvertisingFlags|ManufacturerData|ServiceData):/i.test(detail)) return
    if (match[1].toUpperCase() === "NEW" && !/MX Ergo/i.test(detail)) return
    var address = match[2].toUpperCase()
    if (address === root.recoveryTargetAddress) {
      root.recoverySeenTarget = true
      console.info("MX Ergo recovery: saved address seen in owned scan address=" + address)
      root.startRecoveryConnect()
      return
    }
    if (/MX Ergo/i.test(detail)) {
      root.noteRecoveryOtherAddress(address)
      return
    }
    var list = root.btDevicesList
    for (let i = 0; i < list.length; i++) {
      let device = list[i]
      if (device && String(device.address || "").toUpperCase() === address
          && /MX Ergo/i.test(String(device.name || device.deviceName || ""))) {
        root.noteRecoveryOtherAddress(address)
        return
      }
    }
  }

  function finishRecovery(result) {
    if (root.recoveryStage === "connecting" && root.recoveryDevice
        && root.recoveryDevice.state === BluetoothDeviceState.Connecting
        && result !== "recovery_link_reported") {
      root.abortRecoveryConnect(result)
      return
    }
    recoveryStepTimer.stop()
    recoveryCleanupTimer.stop()
    console.info("MX Ergo recovery: result=" + result
      + " address=" + root.recoveryTargetAddress
      + " freshReport=" + root.recoverySeenTarget
      + " elapsedMs=" + (Date.now() - root.recoveryStartedAt))
    root.recoveryStopping = recoveryScanProcess.running || recoveryCancelProcess.running
    root.recoveryStage = ""
    root.recoveryResult = result
    root.recoveryDevice = null
    root.recoveryAdapter = null
    root.recoveryTargetAddress = ""
    root.recoveryAbortResult = ""
    if (recoveryScanProcess.running) {
      root.recoveryCleanupEscalated = false
      recoveryScanProcess.running = false
    }
    if (recoveryCancelProcess.running) {
      root.recoveryCleanupEscalated = false
      recoveryCancelProcess.running = false
    }
    if (root.recoveryStopping) recoveryCleanupTimer.restart()
  }

  property Timer recoveryStepTimer: Timer {
    repeat: false
    onTriggered: {
      if (root.recoveryStage === "disconnecting") {
        root.finishRecovery("recovery_disconnect_timeout")
      } else if (root.recoveryStage === "startingScan") {
        root.finishRecovery("recovery_scan_start_failed")
      } else if (root.recoveryStage === "scanning") {
        root.startRecoveryConnect()
      } else if (root.recoveryStage === "connecting") {
        root.finishRecovery("recovery_connect_timeout")
      } else if (root.recoveryStage === "cancellingConnect") {
        root.finishRecovery("recovery_cancel_unconfirmed")
      }
    }
  }

  // bluetoothctl owns one BlueZ discovery session even if another client scans.
  // SIGTERM closes only this child's session; never write adapter.discovering.
  property Process recoveryScanProcess: Process {
    command: ["/usr/bin/bluetoothctl", "--timeout", "65", "scan", "le"]
    stdout: SplitParser { onRead: function(line) { root.handleRecoveryScanLine(line) } }
    stderr: SplitParser { onRead: function(line) { root.handleRecoveryScanLine(line) } }
    onExited: {
      if (root.recoveryStage === "startingScan") root.finishRecovery("recovery_scan_start_failed")
      else if (root.recoveryStage !== "" && root.recoveryStage !== "cancellingConnect")
        root.finishRecovery("recovery_scan_ended")
      if (!recoveryCancelProcess.running && root.recoveryStage !== "cancellingConnect") {
        root.recoveryStopping = false
        recoveryCleanupTimer.stop()
      }
    }
  }

  property Process recoveryCancelProcess: Process {
    onExited: function(exitCode) {
      if (root.recoveryStage === "cancellingConnect") {
        if (exitCode !== 0) root.finishRecovery("recovery_cancel_unconfirmed")
        else root.settleRecoveryAbort()
      } else if (!recoveryScanProcess.running) {
        root.recoveryStopping = false
        recoveryCleanupTimer.stop()
      }
    }
  }

  property Timer recoveryCleanupTimer: Timer {
    interval: 2000
    repeat: false
    onTriggered: {
      if (!recoveryScanProcess.running && !recoveryCancelProcess.running) {
        root.recoveryStopping = false
      } else if (!root.recoveryCleanupEscalated) {
        root.recoveryCleanupEscalated = true
        if (recoveryScanProcess.running) recoveryScanProcess.signal(9)
        if (recoveryCancelProcess.running) recoveryCancelProcess.signal(9)
        restart()
      } else {
        root.recoveryResult = "recovery_cleanup_failed"
      }
    }
  }

  property Connections recoveryDeviceEvents: Connections {
    target: root.recoveryDevice
    function onStateChanged() {
      if (root.recoveryStage === "cancellingConnect")
        root.settleRecoveryAbort()
      else if (root.recoveryStage === "disconnecting"
          && root.recoveryDevice.state === BluetoothDeviceState.Connected)
        root.finishRecovery("recovery_disconnect_failed")
      else if (root.recoveryStage === "connecting"
          && root.recoveryDevice.state === BluetoothDeviceState.Disconnected
          && !root.recoveryDevice.connected)
        root.finishRecovery("recovery_connect_failed")
    }
    function onConnectedChanged() {
      if (root.recoveryStage === "cancellingConnect")
        root.settleRecoveryAbort()
      else if (root.recoveryStage === "disconnecting" && !root.recoveryDevice.connected)
        root.startRecoveryScan()
      else if (["startingScan", "scanning", "connecting"].indexOf(root.recoveryStage) >= 0
          && root.recoveryDevice.connected && root.recoverySelectionValid())
        root.finishRecovery("recovery_link_reported")
    }
    function onPairedChanged() {
      if (root.recoveryStage !== "" && root.recoveryStage !== "cancellingConnect"
          && !root.recoveryDevice.paired)
        root.finishRecovery("recovery_unavailable")
    }
    function onBondedChanged() {
      if (root.recoveryStage !== "" && root.recoveryStage !== "cancellingConnect"
          && !root.recoveryDevice.bonded)
        root.finishRecovery("recovery_unavailable")
    }
  }

  property Connections recoveryAdapterEvents: Connections {
    target: root.recoveryAdapter
    function onEnabledChanged() {
      if (root.recoveryStage !== "" && root.recoveryStage !== "cancellingConnect"
          && !root.recoveryAdapter.enabled)
        root.finishRecovery("recovery_unavailable")
    }
  }

  onCanRecoverChanged: {
    if (root.recoveryStage !== "" && root.recoveryStage !== "cancellingConnect"
        && !root.canRecover)
      root.finishRecovery("recovery_unavailable")
  }
  onTargetAddressChanged: {
    if (root.recoveryStage !== "" && root.recoveryStage !== "cancellingConnect")
      root.finishRecovery("recovery_unavailable")
  }
  onBtDevicesListChanged: {
    if (root.recoveryStage !== "") root.updateRecoveryOtherState()
  }
  onBleLinkedChanged: {
    if (root.bleLinked && root.targetAddress === "")
      root.observedBtAddress = String(root.btDevice.address).toUpperCase()
  }
  onBtDeviceChanged: {
    if (startupRecoveryTimer.running && root.btDevice !== root.startupRecoveryDevice) {
      root.startupRecoveryAttempted = true
      startupRecoveryTimer.stop()
      root.startupRecoveryDevice = null
    }
    if (root.recoveryStage !== "" && root.recoveryStage !== "cancellingConnect"
        && root.btDevice !== root.recoveryDevice)
      root.finishRecovery("recovery_unavailable")
    if (root.wakeRetryDevice && root.btDevice !== root.wakeRetryDevice) {
      root.wakeRetryDevice = null
      wakeStage2Timer.stop()
      wakeRetryDeadline.stop()
    }
  }

  property Connections wakeDeviceEvents: Connections {
    target: root.wakeRetryDevice
    function onStateChanged() {
      if (root.wakeRetryDevice && root.btDevice === root.wakeRetryDevice
          && !wakeStage2Timer.running
          && root.wakeRetryDevice.state !== BluetoothDeviceState.Connecting)
        root.finishWakeRetry()
    }
  }

  function finishWakeRetry() {
    var device = root.wakeRetryDevice
    root.wakeRetryDevice = null
    wakeRetryDeadline.stop()
    if (device && root.btDevice === device && root.autoReconnect
        && !root.connected && !root.sleeping && !root.shuttingDown)
      root.reconnectDevice()
  }

  function setAutoReconnect(enabled) {
    var b = !!enabled
    if (root.autoReconnect !== b) {
      root.autoReconnect = b
      saveDebounce.restart()
    }
  }

  // The process lifetime includes the Polkit prompt; do not guess with a 3s timer.
  function checkLowLatency(preserveError) {
    if (root.lowLatencyBusy || root.sleeping || root.shuttingDown) return
    if (lowLatencyCheck.running) return
    if (preserveError !== true) root.lowLatencyFailed = false
    root.lowLatencyState = "unknown"
    root.lowLatencyConfigured = false
    root.lowLatencyHelperAvailable = false
    root.lowLatencyCanRestore = false
    root.lowLatencyLegacy = false
    latencyStatusProcess.adapterAtStart = root.bluetoothAdapter
    lowLatencyCheck.command = [root.lowLatencyScript, "--status", root.bluetoothAdapter || "-"]
    lowLatencyCheck.running = true
  }

  function applyLowLatency() {
    runLowLatency("--enable")
  }

  function revertLowLatency() {
    runLowLatency("--disable")
  }

  function runLowLatency(action) {
    if (root.lowLatencyBusy || !root.lowLatencyHelperAvailable) return
    if (["--enable", "--disable", "--remove-legacy"].indexOf(action) < 0) return
    if (action === "--enable" && !/^hci[0-9]+$/.test(root.bluetoothAdapter)) return
    lowLatencyCheck.running = false
    root.lowLatencyFailed = false
    lowLatencyApply.command = [root.lowLatencyScript, action, root.bluetoothAdapter || "-"]
    lowLatencyApply.running = true
  }

  property Process lowLatencyApply: Process {
    onExited: function(exitCode) {
      root.lowLatencyFailed = exitCode !== 0
      Qt.callLater(function() { root.checkLowLatency(true) })
    }
  }

  property Process lowLatencyCheck: Process {
    id: latencyStatusProcess
    property string adapterAtStart: ""
    onExited: {
      if (adapterAtStart !== root.bluetoothAdapter) Qt.callLater(root.checkLowLatency)
    }
    stdout: StdioCollector {
      onStreamFinished: {
        if (latencyStatusProcess.adapterAtStart !== root.bluetoothAdapter || root.lowLatencyBusy) return
        try {
          let result = JSON.parse(text)
          root.lowLatencyHelperAvailable = result.version === 1 && result.helperAvailable === true
          root.lowLatencyCanRestore = result.canRestore === true
          root.lowLatencyLegacy = result.state === "legacy"
          root.lowLatencyConfigured = result.configured === true
          root.lowLatencyState = ["applied", "partial", "off", "unknown", "unavailable", "legacy", "restart", "restore_pending"].indexOf(result.state) >= 0 ? result.state : "unknown"
        } catch (e) {
          root.lowLatencyState = "unknown"
        }
      }
    }
  }

  property Timer connectingResetTimer: Timer {
    interval: 8000
    repeat: false
    onTriggered: { root.isConnecting = false }
  }

  // MAC / hardware address
  readonly property string macAddress: {
    if (root.matchedPower) return root.matchedPower.identity.address
    if (btDevice && btDevice.address) return String(btDevice.address).toUpperCase()
    if (root.targetAddress !== "") return root.targetAddress.toUpperCase()
    return "046D:B01D"
  }

  // Every level is approximate: this MX Ergo interface does not expose verified SOC.
  readonly property string batteryTier: Battery.tier(root.connected, root.isCharging,
    root.matchedPower ? root.matchedPower.capacityLevel : "",
    root.upDevice ? root.upDevice.iconName : "",
    !!(root.bleLinked && root.btDevice.batteryAvailable),
    root.btDevice ? root.btDevice.battery : null)
  // Show the reported category; the hint explains that exact charge is unavailable.
  readonly property string batteryLevelText: Battery.label(root.connected, root.isCharging, root.batteryTier,
    function(key) { return root.t(key) })
  readonly property string batteryReportText: root.batteryTier || root.isCharging
    ? root.t("battery_reported")
    : root.t("battery_estimate_hint")
  readonly property string batterySourceDifference: {
    if (!root.connected || !root.matchedPower || !root.bleLinked
        || !root.btDevice.batteryAvailable) return ""
    var hid = Battery.levelTier(root.matchedPower.capacityLevel)
    var ble = Battery.reportedTier(root.btDevice.battery)
    if (!hid || !ble || hid === ble) return ""
    return "HID++: " + root.t("battery_" + hid)
      + " · Bluetooth: " + root.t("battery_" + ble)
  }
  readonly property string batteryIcon: root.isCharging ? "󰂄" : "󰂑"

  readonly property string transportText: {
    if (root.transport === "ble") return I18n.t("transport_ble", root.effectiveLanguage)
    if (root.transport === "unifying") return I18n.t("transport_unifying", root.effectiveLanguage)
    return I18n.t("disconnected", root.effectiveLanguage)
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
      let command = "omarchy-shell io.github.pavellizunov.mx-ergo " + (axis ? "nextProfileFromWheel" : "nextProfile")
      lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Next Profile\", " + JSON.stringify(command)
        + ", { release = " + (axis ? "false" : "true") + " })\n"
    } else if (action === "workspace_next") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Next Workspace\", hl.dsp.focus({ workspace = \"e+1\" }))\n"
    } else if (action === "workspace_prev") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Prev Workspace\", hl.dsp.focus({ workspace = \"e-1\" }))\n"
    } else if (action === "window_close") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Close Window\", hl.dsp.window.close())\n"
    } else if (action === "window_float") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Toggle Floating\", hl.dsp.window.float({ action = \"toggle\" }))\n"
    } else if (action === "window_fullscreen") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Fullscreen\", hl.dsp.window.fullscreen({ mode = \"fullscreen\" }))\n"
    } else if (action === "window_next") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Next Window\", hl.dsp.window.cycle_next())\n"
    } else if (action === "overview") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Overview\", \"omarchy-shell moorgrove.overview toggle\")\n"
    } else if (action === "screenshot") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Screenshot\", \"omarchy-capture-screenshot\")\n"
    } else if (action === "media_play_pause") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Play/Pause\", \"playerctl play-pause\")\n"
    } else if (action === "media_next") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Next Track\", \"playerctl next\")\n"
    } else if (action === "media_prev") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Prev Track\", \"playerctl previous\")\n"
    } else if (action === "mute") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Toggle Mute\", \"wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle\")\n"
    } else if (action === "tab_next") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Next Tab\", \"wtype -M ctrl -k Tab\")\n"
    } else if (action === "tab_prev") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Prev Tab\", \"wtype -M ctrl -M shift -k Tab\")\n"
    } else if (action === "browser_back") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Browser Back\", \"wtype -M alt -k Left\")\n"
    } else if (action === "browser_forward") {
      lua += "o.bind(\"" + code + "\", \"MX Ergo: Browser Forward\", \"wtype -M alt -k Right\")\n"
    } else if (action === "custom_shortcut") {
      let sc = buttonProfile ? buttonProfile.customShortcuts[btnKey] : getCustomShortcut(btnKey)
      if (sc !== "") {
        let norm = sc.toUpperCase().replace(/,/g, " ").replace(/\+/g, " ").trim().replace(/\s+/g, " ")
        let wsMatch = norm.match(/^(SUPER|WIN|LOGO)\s+([0-9]+)$/)
        if (wsMatch) {
          lua += "o.bind(" + JSON.stringify(code) + ", " + JSON.stringify("MX Ergo: Workspace " + wsMatch[2]) + ", hl.dsp.focus({ workspace = \"" + wsMatch[2] + "\" }))\n"
        } else if (norm === "SUPER CTRL TAB" || norm === "SUPER CONTROL TAB" || norm === "WIN CTRL TAB" || norm === "WIN CONTROL TAB") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Former Workspace\", hl.dsp.focus({ workspace = \"previous\" }))\n"
        } else if (norm === "SUPER SHIFT TAB" || norm === "WIN SHIFT TAB") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Prev Workspace\", hl.dsp.focus({ workspace = \"e-1\" }))\n"
        } else if (norm === "SUPER TAB" || norm === "WIN TAB") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Next Workspace\", hl.dsp.focus({ workspace = \"e+1\" }))\n"
        } else if (norm === "SUPER W" || norm === "SUPER Q" || norm === "WIN W" || norm === "WIN Q") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Close Window\", hl.dsp.window.close())\n"
        } else if (norm === "SUPER F" || norm === "WIN F") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Fullscreen\", hl.dsp.window.fullscreen({ mode = \"fullscreen\" }))\n"
        } else if (norm === "SUPER T" || norm === "WIN T") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Toggle Float\", hl.dsp.window.float({ action = \"toggle\" }))\n"
        } else if (norm === "SUPER SPACE" || norm === "WIN SPACE") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Menu\", \"omarchy-menu toggle\")\n"
        } else if (norm === "SUPER S" || norm === "WIN S") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Scratchpad\", hl.dsp.workspace.toggle_special(\"scratchpad\"))\n"
        } else if (norm === "SUPER LEFT" || norm === "WIN LEFT") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Focus Left\", hl.dsp.focus({ direction = \"l\" }))\n"
        } else if (norm === "SUPER RIGHT" || norm === "WIN RIGHT") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Focus Right\", hl.dsp.focus({ direction = \"r\" }))\n"
        } else if (norm === "SUPER UP" || norm === "WIN UP") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Focus Up\", hl.dsp.focus({ direction = \"u\" }))\n"
        } else if (norm === "SUPER DOWN" || norm === "WIN DOWN") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Focus Down\", hl.dsp.focus({ direction = \"d\" }))\n"
        } else if (norm === "INSERT" || norm === "INS") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Voxtype Dictation\", \"voxtype record toggle\")\n"
        } else if (norm === "SUPER INSERT" || norm === "WIN INSERT") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Voice Agent\", \"omarchy-voice-agent toggle || omarchy-voice-agent start\")\n"
        } else if (norm === "SUPER ALT A" || norm === "WIN ALT A") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: TTS Clipboard\", " + JSON.stringify(shellQuote(root.configHome + "/omarchy/plugins/io.github.hikari112.tts/bin/speak") + " --clipboard") + ")\n"
        } else if (norm === "SUPER ALT E" || norm === "WIN ALT E") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: TTS Selection\", " + JSON.stringify(shellQuote(root.configHome + "/omarchy/plugins/io.github.hikari112.tts/bin/speak") + " --toggle") + ")\n"
        } else if (norm === "SUPER ALT X" || norm === "WIN ALT X") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: TTS Stop\", " + JSON.stringify(shellQuote(root.configHome + "/omarchy/plugins/io.github.hikari112.tts/bin/speak") + " --stop") + ")\n"
        } else if (norm === "SUPER ALT R" || norm === "WIN ALT R") {
          lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: TTS Snip\", " + JSON.stringify(shellQuote(root.configHome + "/omarchy/plugins/io.github.hikari112.tts/bin/speak") + " --snip") + ")\n"
        } else {
          let wcmd = shortcutToWtype(sc)
          if (wcmd !== "") {
            lua += "o.bind(" + JSON.stringify(code) + ", " + JSON.stringify("MX Ergo: " + sc) + ", " + JSON.stringify(wcmd) + ")\n"
          }
        }
      }
    } else if (action === "custom_command") {
      let rawCmd = buttonProfile ? buttonProfile.customCommands[btnKey] : getCustomCommand(btnKey)
      if (rawCmd !== "") {
        lua += "o.bind(" + JSON.stringify(code) + ", \"MX Ergo: Command\", " + JSON.stringify(rawCmd) + ")\n"
      }
    }
    return lua
  }

  function applyButtonBind(btnKey, action) { applyAllSettings() }

  function buildSettingsRequest() {
    var tx = root.profileTransaction
    var selected = tx ? Profiles.find(root.buttonProfiles, tx.rollback ? tx.fromId : tx.toId) : null
    var lua = "do\n"
    if (root.hyprDeviceName !== "") {
      let sensitivity = Number(root.sensitivity)
      if (!isFinite(sensitivity)) throw new Error("Invalid sensitivity")
      let profile = root.accelProfile
      if (profile !== "adaptive" && profile !== "flat") throw new Error("Invalid acceleration profile")
      lua += "hl.device({ name = " + JSON.stringify(root.hyprDeviceName)
        + ", sensitivity = " + Math.max(-1, Math.min(1, sensitivity)).toFixed(2)
        + ", accel_profile = " + JSON.stringify(profile)
        + ", natural_scroll = " + (root.naturalScroll ? "true" : "false") + " })\n"
    }
    var buttons = { "mouse:275": "back", "mouse:276": "forward", "mouse:274": "middle",
      "mouse_left": "tiltLeft", "mouse:278": "tiltLeft", "mouse_right": "tiltRight", "mouse:279": "tiltRight" }
    var expected = {}
    for (let code in buttons) {
      let key = buttons[code]
      let action = selected ? selected.buttons[key] : getButtonAction(key)
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
      console.warn("MX Ergo: invalid settings; application skipped")
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
    if (ok) console.info("MX Ergo: settings applied and button bindings verified")
    else console.warn("MX Ergo: settings verification failed after bounded recovery")
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
    root.recoveryStage = ""
    recoveryStepTimer.stop()
    recoveryCleanupTimer.stop()
    recoveryScanProcess.running = false
    recoveryCancelProcess.running = false
    startupRecoveryTimer.stop()
    sleepRetry.stop()
    sleepStartCheck.stop()
    wakeReconnectTimer.stop()
    wakeStage2Timer.stop()
    wakeRetryDeadline.stop()
    root.wakeRetryDevice = null
    saveDebounce.stop()
    profileWheelLatch.stop()
    applyDebounce.stop()
    sleepMonitor.running = false
    pendingSettingsRequest = null
    settingsStartCheck.stop()
    settingsDeadline.stop()
    if (settingsApplier.running) settingsApplier.running = false
  }

  // Config persistence (saves to ~/.config/omarchy/mx-ergo.json via safe discrete argv without shell execution)
  function saveConfig() {
    if (!root.configReadComplete || root.profileBusy || root.configLoadFailed) return
    root.storeActiveProfile()
    var cfg = {
      version: 2,
      sensitivity: root.sensitivity,
      accelProfile: root.accelProfile,
      naturalScroll: root.naturalScroll,
      autoReconnect: root.autoReconnect,
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
    else console.warn("MX Ergo: preferences could not be saved")
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
      if (exitCode !== 0) console.warn("MX Ergo: invalid or unreadable preferences; using defaults without applying them")
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
          if (typeof cfg.autoReconnect === "boolean") root.autoReconnect = cfg.autoReconnect
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
      root.startupRecoveryAttempted = true
      startupRecoveryTimer.stop()
      if (root.recoveryStage !== "" && root.recoveryStage !== "cancellingConnect")
        root.finishRecovery("recovery_cancelled")
      wakeReconnectTimer.stop()
      wakeStage2Timer.stop()
      wakeRetryDeadline.stop()
      root.wakeRetryDevice = null
      if (settingsApplier.running) settingsApplier.signal(15)
    } else {
      root.sleepMonitorRestarts = 0
      root.sleepMonitorFailed = false
      if (root.settingsConfigured) root.applyAllSettings()
      if (root.autoReconnect) wakeReconnectTimer.restart()
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

  // One owned, bounded scan after startup; a live or manually repaired link
  // consumes the opportunity so an ordinary later disconnect does not scan.
  property Timer startupRecoveryTimer: Timer {
    interval: 5000
    repeat: false
    onTriggered: root.startStartupRecovery()
  }

  // Bounded reconnection attempts after the controller has had time to resume.
  property Timer wakeReconnectTimer: Timer {
    interval: 2000
    repeat: false
    onTriggered: {
      if (root.autoReconnect && !root.connected && !root.sleeping) {
        if (root.reconnectDevice()) {
          root.wakeRetryDevice = root.btDevice
          // Wait for the first Quickshell Connect to settle before retrying.
          wakeStage2Timer.restart()
          wakeRetryDeadline.restart()
        }
      }
    }
  }

  property Timer wakeStage2Timer: Timer {
    interval: 10000
    repeat: false
    onTriggered: {
      if (root.wakeRetryDevice
          && root.wakeRetryDevice.state !== BluetoothDeviceState.Connecting)
        root.finishWakeRetry()
    }
  }
  property Timer wakeRetryDeadline: Timer {
    interval: 60000
    repeat: false
    onTriggered: { root.wakeRetryDevice = null }
  }

  Component.onCompleted: {
    console.info("MX Ergo: model loaded with categorical battery display and Hyprland reload recovery")
    console.info("MX Ergo: named button profiles v2 ready")
    Qt.callLater(root.logConnectionState)
    root.loadProfileConfig(null)
    checkLowLatency()
    configLoader.running = true
    configReadStartCheck.restart()
    sleepMonitor.running = true
    sleepStartCheck.restart()
  }
}
