import QtQuick
import QtQuick.Effects
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.pavellizunov.mx-ergo"
  ipcTarget: "io.github.pavellizunov.mx-ergo"
  manageIpc: false
  onOpenedChanged: if (opened) panelCard.showPage("buttons")

  // Loader settings can lag an inline edit after a plugin reload. The scoped
  // host facade carries the current persisted entry, without rebuilding widgets.
  function resolveSettings(config, fallback) {
    var layout = config && config.layout
    var matches = []
    if (layout) ["left", "center", "right"].forEach(function(section) {
      var entries = layout[section]
      if (!Array.isArray(entries)) return
      entries.forEach(function(entry) {
        if (entry && entry.id === root.moduleName) matches.push(entry)
      })
    })
    return matches.length === 1 ? matches[0] : fallback
  }
  readonly property var currentSettings: resolveSettings(
    root.bar && root.bar.shell ? root.bar.shell.barConfig : null, root.settings)
  function currentSetting(name, fallback) {
    var value = currentSettings ? currentSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function connectionStatus(): string {
      return JSON.stringify({target: ergoModel.targetAddress,
        address: ergoModel.btDevice ? ergoModel.btDevice.address : "",
        connected: ergoModel.connected, transport: ergoModel.transport,
        canRecover: ergoModel.canRecover, canStartRecovery: ergoModel.canStartRecovery,
        busy: ergoModel.recoveryBusy, stage: ergoModel.recoveryStage,
        result: ergoModel.recoveryResult, panelOpen: root.opened,
        page: panelCard.panelPage, recoveryVisible: panelCard.recoveryVisible})
    }
    function recoverConnection(): bool { return ergoModel.recoverDevice() }
    function nextProfile(): void { ergoModel.nextProfile() }
    function nextProfileFromWheel(): void { ergoModel.nextProfileFromWheel() }
    function profileStatus(): string {
      return JSON.stringify({id: ergoModel.activeProfileId, name: ergoModel.activeProfileName,
        count: ergoModel.buttonProfiles.length, buttons: ergoModel.captureButtonProfile().buttons,
        busy: ergoModel.profileBusy, error: ergoModel.profileError,
        configured: ergoModel.settingsConfigured, applying: ergoModel.settingsApplying,
        applyFailed: ergoModel.settingsRecoveryFailed, loadFailed: ergoModel.configLoadFailed,
        verified: ergoModel.settingsVerified, pending: ergoModel.settingsPending,
        savePending: ergoModel.configPending, saveFailed: ergoModel.configSaveFailed,
        saved: ergoModel.configStored && !ergoModel.configPending && !ergoModel.configSaveFailed && !ergoModel.configLoadFailed})
    }
  }

  readonly property bool hideWhenDisconnected: root.currentSetting("hideWhenDisconnected", true)
  readonly property bool vertical: root.bar ? root.bar.vertical : false

  ErgoModel {
    id: ergoModel
    targetAddress: root.currentSetting("deviceAddress", "")
    hyprDeviceName: root.currentSetting("hyprDeviceName", "logitech-mx-ergo-multi-device-trackball-")
    sensitivity: root.currentSetting("sensitivity", 0.0)
    accelProfile: root.currentSetting("accelProfile", "adaptive")
    naturalScroll: root.currentSetting("naturalScroll", false)
    language: root.currentSetting("locale", "system")
    panelOpen: root.opened
    onLocaleRequested: function(code) {
      if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
        let entry = Object.assign({}, root.currentSettings || {}, {
          id: root.moduleName,
          locale: code
        })
        root.bar.shell.updateEntryInline(root.moduleName, entry)
      }
    }
  }

  visible: ergoModel.connected || !root.hideWhenDisconnected
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Style.bar.iconSlot
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    horizontalMargin: 0
    verticalPadding: 0
    tooltipText: "Logitech MX Ergo: " + ergoModel.connectionStatusText
      + (ergoModel.connected ? " · " + ergoModel.batteryLevelText : "")
      + " · " + ergoModel.activeProfileName
    onPressed: function(b) {
      root.toggle()
    }

    Row {
      id: barContent
      anchors.centerIn: parent
      spacing: Style.space(3)

      Item {
        id: trackballIcon
        readonly property color foreground: button.active && button.useActiveColor ? button.activeColor : button.foreground
        width: Style.bar.iconCanvas
        height: width
        anchors.verticalCenter: parent.verticalCenter

        Image {
          id: trackballSource
          anchors.fill: parent
          source: Qt.resolvedUrl("assets/trackball.svg")
          sourceSize.width: Math.ceil(width * 4)
          sourceSize.height: Math.ceil(height * 4)
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          visible: false
        }

        MultiEffect {
          anchors.fill: parent
          source: trackballSource
          colorization: 1
          colorizationColor: trackballIcon.foreground
        }

        Rectangle {
          anchors.centerIn: parent
          visible: !ergoModel.connected
          width: parent.width
          height: Style.space(1.5)
          radius: height / 2
          rotation: -45
          antialiasing: true
          color: trackballIcon.foreground
        }
      }

      // Charging micro-bolt
      Text {
        visible: ergoModel.connected && ergoModel.isCharging
        textFormat: Text.PlainText
        text: "󰂄"
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    open: root.opened
    bar: root.bar
    focusTarget: panelCard
    contentWidth: popup.fittedContentWidth(panelCard.preferredWidth)
    contentHeight: popup.fittedContentHeight(panelCard.contentHeight, popup.availableCardHeight * 0.95)

    ErgoPanel {
      id: panelCard
      anchors.fill: parent
      panelInset: popup.contentWidth - width
      bar: root.bar
      model: ergoModel
      onCloseRequested: root.close()
    }
  }
}
