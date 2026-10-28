import QtQuick
import QtQuick.Effects
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

// Trackball controls hosted by the shell keyboard panel.
PanelKeyCatcher {
  id: root

  component ActionButton: Button {
    id: control
    focusable: true
    Accessible.role: Accessible.Button
    Accessible.name: control.text
    Accessible.onPressAction: if (control.enabled) control.clicked()
  }

  blocked: root.isRecording || profilesSection.ownsFocus || profilesSection.popupOpen
    || actionPicker.popupOpen || (shortcutInput && shortcutInput.activeFocus) || (cmdField && cmdField.activeFocus)

  required property QtObject bar
  required property QtObject model

  property int focusIndex: 4
  property bool cursorActive: false
  property string panelPage: "buttons"
  property bool editingButton: false
  readonly property bool recoveryVisible: connectButton.visible
  Connections {
    target: root.model
    function onActiveProfileIdChanged() {
      if (root.editingButton) root.showPage("buttons")
    }
    function onLowLatencyBusyChanged() {
      if (root.model.lowLatencyBusy) root.advancedExpanded = true
    }
    function onLowLatencyFailedChanged() {
      if (root.model.lowLatencyFailed) root.advancedExpanded = true
    }
  }
  readonly property var languageCodes: ["system", "en", "zh", "es", "ru", "pt", "fr", "de", "ja", "ko", "it"]

  function resetViewport() {
    root.forceActiveFocus()
    Qt.callLater(function () { viewport.contentY = 0; settingsViewport.contentY = 0 })
  }

  function showPage(page) {
    if (page !== "buttons" && page !== "pointer" && page !== "device") return
    root.isRecording = false
    root.editingButton = false
    root.languageExpanded = false
    profilesSection.reset()
    root.panelPage = page
    root.focusIndex = root.cursorActive ? -1 : (page === "buttons" ? 4 : page === "pointer" ? 0 : 5)
    resetViewport()
  }

  function editButton(key) {
    if (root.model.profileBusy) return
    if (!root.buttonList.some(function (button) { return button.key === key })) return
    profilesSection.reset()
    root.selectedButton = key
    root.isRecording = false
    root.languageExpanded = false
    root.panelPage = "buttons"
    root.editingButton = true
    syncActiveButton()
    actionPicker.categoryIndex = actionPicker.categoryFor(root.selectedAction)
    shortcutInput.text = root.model.getCustomShortcut(key)
    cmdField.text = root.model.getCustomCommand(key)
    root.forceActiveFocus()
    Qt.callLater(function () { editorViewport.contentY = 0 })
  }

  function closeButtonEdit() {
    root.isRecording = false
    root.editingButton = false
    root.focusIndex = 4
    root.forceActiveFocus()
  }

  function finishButtonEdit() {
    root.isRecording = false
  }

  Keys.onEscapePressed: function (event) {
    if (root.isRecording) root.isRecording = false
    else if (root.languageExpanded) { root.languageExpanded = false; root.focusIndex = -2; root.forceActiveFocus() }
    else if (root.editingButton) root.closeButtonEdit()
    else root.closeRequested()
    event.accepted = true
  }


  // Selected physical button: "back" | "forward" | "middle" | "tiltLeft" | "tiltRight"
  property string selectedButton: "back"
  // Button setup mode: "presets" | "shortcut" | "command"
  property string setupMode: "presets"
  // Shortcut recording active flag
  property bool isRecording: false
  // Language picker expanded flag
  property bool languageExpanded: false
  property bool advancedExpanded: false
  readonly property bool advancedVisible: advancedExpanded
  // Function keys expanded flag
  property bool fKeysExpanded: false

  readonly property color fgColor: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.rgba(fgColor.r, fgColor.g, fgColor.b, 0.85)
  readonly property string fontFam: bar ? bar.fontFamily : Style.font.family

  property real panelInset: 0
  readonly property real preferredWidth: Style.space(736)
  readonly property real overviewWidth: Math.max(0, Math.min(width, Style.space(380) - panelInset) - Style.spacing.controlGap)
  readonly property real contentHeight: Style.space(650)

  readonly property var buttonList: [
    { key: "back", labelKey: "btn_back" },
    { key: "forward", labelKey: "btn_forward" },
    { key: "middle", labelKey: "btn_middle" },
    { key: "tiltLeft", labelKey: "btn_tilt_left" },
    { key: "tiltRight", labelKey: "btn_tilt_right" }
  ]

  readonly property string selectedAction: root.model.getButtonAction(root.selectedButton)
  onSelectedActionChanged: syncActiveButton()
  readonly property bool assignmentDraft: root.setupMode === "shortcut"
    ? shortcutInput.text.trim() !== root.model.getCustomShortcut(root.selectedButton).trim()
    : root.setupMode === "command"
      && cmdField.text.trim() !== root.model.getCustomCommand(root.selectedButton).trim()
  readonly property string assignmentStatusKey: root.model.configLoadFailed ? "settings_load_error"
    : root.model.settingsPending ? "assignment_applying"
    : root.model.configPending ? "assignment_saving"
    : root.model.settingsRecoveryFailed ? "assignment_apply_error"
    : root.model.configSaveFailed ? "settings_save_error"
    : root.model.settingsVerified && root.model.configStored ? "assignment_done"
    : "assignment_unverified"

  function selectedButtonLabel() {
    for (let i = 0; i < buttonList.length; ++i)
      if (buttonList[i].key === selectedButton) return root.model.t(buttonList[i].labelKey)
    return ""
  }

  onFocusIndexChanged: Qt.callLater(ensureCursorVisible)
  function ensureCursorVisible() {
    if (!cursorActive || editingButton) return
    if (focusIndex === -2 || focusIndex === -1) { viewport.contentY = 0; return }
    var target = focusIndex >= 10 ? languageGrid : focusIndex === 7 ? profilesSection : focusIndex === -3 ? connectButton : focusIndex === -4 ? retrySettingsButton : focusIndex <= 1 ? profileRow : focusIndex === 2 ? sensitivityColumn
      : focusIndex === 3 ? naturalRow : focusIndex === 5 ? autoReconnectRow : focusIndex === 6 ? advancedButton : focusIndex === 8 ? profileAction : (btnSelectorRow.selectedControl || btnSelectorRow)
    // Shared context/status is on the left; page controls scroll on the right.
    var area = focusIndex >= 10 || focusIndex === 7 || focusIndex === 4 || focusIndex === -4
      ? viewport : settingsViewport
    if (focusIndex === -3) return // Recovery is in the fixed header.
    var y = target.mapToItem(area.contentItem, 0, 0).y
    var next = y < area.contentY ? y : Math.max(area.contentY, y + target.height - area.height)
    area.contentY = Math.max(0, Math.min(area.contentHeight - area.height, next))
  }

  function stepFocus(dir) {
    cursorActive = true
    if (editingButton) {
      let controls = []
      collectEditorControls(editorColumn, controls)
      if (controls.length === 0) return
      let current = controls.findIndex(function (control) { return control.activeFocus })
      let index = current < 0 ? (dir > 0 ? 0 : controls.length - 1)
        : (current + dir + controls.length) % controls.length
      let target = controls[index]
      target.forceActiveFocus()
      let y = target.mapToItem(editorViewport.contentItem, 0, 0).y
      editorViewport.contentY = Math.max(0, Math.min(editorViewport.contentHeight - editorViewport.height,
        y < editorViewport.contentY ? y : Math.max(editorViewport.contentY, y + target.height - editorViewport.height)))
      return
    }
    root.forceActiveFocus()
    var order = [-2]
    if (languageExpanded) for (let code = 0; code < languageCodes.length; code++) order.push(10 + code)
    if (connectButton.visible && connectButton.enabled) order.push(-3)
    if (retrySettingsButton.visible && retrySettingsButton.enabled) order.push(-4)
    order = order.concat([-1, 7, 4], panelPage === "pointer" ? [0, 1, 2, 3] : panelPage === "device" ? [5] : [])
    if (panelPage === "device") {
      order.push(6)
      if (root.advancedVisible && profileAction.enabled) order.push(8)
    }
    var index = order.indexOf(focusIndex)
    focusIndex = order[(index + dir + order.length) % order.length]
  }

  function collectEditorControls(item, controls) {
    if (!item.visible || !item.enabled) return
    if (item.activeFocusOnTab) { controls.push(item); return }
    for (let i = 0; i < item.children.length; ++i) collectEditorControls(item.children[i], controls)
  }

  function syncActiveButton() {
    var act = root.model.getButtonAction(root.selectedButton)
    if (act === "custom_shortcut") {
      root.setupMode = "shortcut"
    } else if (act === "custom_command") {
      root.setupMode = "command"
    } else {
      root.setupMode = "presets"
    }
  }

  function addTokenToShortcut(token) {
    var cur = shortcutInput ? shortcutInput.text.trim() : ""
    var isMod = (token === "SUPER" || token === "CTRL" || token === "ALT" || token === "SHIFT")
    var nextText = ""
    if (cur === "") {
      nextText = isMod ? (token + " + ") : token
    } else if (cur.endsWith("+")) {
      nextText = cur + " " + token
    } else {
      if (isMod) {
        let parts = cur.split(/\s*\+\s*/)
        let idx = parts.indexOf(token)
        if (idx !== -1) {
          parts.splice(idx, 1)
          nextText = parts.join(" + ")
        } else {
          parts.unshift(token)
          nextText = parts.join(" + ")
        }
      } else {
        nextText = cur + " + " + token
      }
    }
    if (shortcutInput) shortcutInput.text = nextText
  }

  onSelectedButtonChanged: {
    root.isRecording = false
    syncActiveButton()
    Qt.callLater(ensureCursorVisible)
  }

  Component.onCompleted: {
    syncActiveButton()
    if (root.model.lowLatencyBusy || root.model.lowLatencyFailed) root.advancedExpanded = true
  }

  function handleMove(dx, dy) {
    cursorActive = true
    if (editingButton) return
    if (focusIndex === -2 || focusIndex === -3 || focusIndex === -4 || focusIndex >= 10) {
      stepFocus(dx || dy)
      return
    }
    if (focusIndex === -1) {
      if (dx !== 0) {
        let pages = ["buttons", "pointer", "device"]
        showPage(pages[(pages.indexOf(panelPage) + (dx > 0 ? 1 : -1) + pages.length) % pages.length])
      }
      else if (dy !== 0) focusIndex = panelPage === "buttons" ? 4 : panelPage === "pointer" ? 0 : 5
      return
    }
    if (focusIndex === 7) { profilesSection.focusFirst(); return }
    if (focusIndex === 4) {
      let direction = dx || dy
      if (direction !== 0) {
        let index = buttonList.findIndex(function (button) { return button.key === selectedButton })
        selectedButton = buttonList[(index + (direction > 0 ? 1 : -1) + buttonList.length) % buttonList.length].key
      }
      return
    }
    if (panelPage === "device") { stepFocus(dx || dy); return }
    if (dy !== 0) {
      if (dy > 0) {
        if (focusIndex <= 1) focusIndex = 2
        else if (focusIndex === 2) focusIndex = 3
        else if (focusIndex === 3) focusIndex = -1
        else focusIndex = 0
      } else {
        if (focusIndex === 0 || focusIndex === 1) focusIndex = -1
        else if (focusIndex === 2) focusIndex = 0
        else if (focusIndex === 3) focusIndex = 2
      }
      return
    }

    if (dx !== 0) {
      if (focusIndex <= 1) {
        focusIndex = dx > 0 ? 1 : 0
      } else if (focusIndex === 2) {
        root.model.setSensitivity(root.model.sensitivity + dx * 0.05)
      } else if (focusIndex === 3) {
        root.model.setNaturalScroll(!root.model.naturalScroll)

      }
    }
  }

  function activateBluetoothProfile() {
    if (!root.model.lowLatencyHelperAvailable || root.model.lowLatencyBusy || root.model.lowLatencyState === "restart") return
    if (root.model.lowLatencyLegacy) root.model.runLowLatency("--remove-legacy")
    else if (root.model.lowLatencyCanRestore) root.model.revertLowLatency()
    else root.model.applyLowLatency()
  }

  function handleActivate() {
    cursorActive = true
    if (editingButton) return
    if (focusIndex === -2) { root.languageExpanded = !root.languageExpanded; return }
    if (focusIndex >= 10 && focusIndex < 10 + languageCodes.length) {
      root.model.setLocale(languageCodes[focusIndex - 10])
      root.languageExpanded = false
      root.focusIndex = -2
      return
    }
    if (focusIndex === -3) {
      if (root.model.recoveryStage !== "") root.model.cancelRecovery()
      else root.model.recoverDevice()
      return
    }
    if (focusIndex === -4) {
      if (retrySettingsButton.visible && retrySettingsButton.enabled) root.model.retrySettings()
      return
    }
    if (focusIndex < 0) return
    if (focusIndex === 7) { profilesSection.focusFirst(); return }
    if (focusIndex === 4) { if (!root.model.profileBusy) editButton(selectedButton); return }
    if (panelPage === "device") {
      if (focusIndex === 5) root.model.setAutoReconnect(!root.model.autoReconnect)
      else if (focusIndex === 6) root.advancedExpanded = !root.advancedExpanded
      else if (focusIndex === 8) root.activateBluetoothProfile()
      return
    }
    if (focusIndex === 0) {
      root.model.setAccelProfile("adaptive")
    } else if (focusIndex === 1) {
      root.model.setAccelProfile("flat")
    } else if (focusIndex === 2) {
      root.model.setSensitivity(0.0)
    } else if (focusIndex === 3) {
      root.model.setNaturalScroll(!root.model.naturalScroll)
    }
  }

  onTabRequested: function(dir) { root.stepFocus(dir) }
  onMoveRequested: function(dx, dy) { root.handleMove(dx, dy) }
  onActivateRequested: root.handleActivate()

  readonly property bool editorPopupOpen: actionPicker.popupOpen || profilesSection.popupOpen || root.languageExpanded
  property bool backgroundPopupGuard: false
  onEditorPopupOpenChanged: {
    if (root.editorPopupOpen) root.backgroundPopupGuard = true
    else Qt.callLater(function() { root.backgroundPopupGuard = root.editorPopupOpen })
  }

  component EditorDismissArea: MouseArea {
    enabled: root.editingButton
    acceptedButtons: Qt.LeftButton
    property point pressPosition
    property bool moved: false
    property bool dismissOnRelease: false
    // Popup closure can forward the same press. Capture its guard before releasing.
    onPressed: function(mouse) {
      pressPosition = Qt.point(mouse.x, mouse.y)
      moved = false
      dismissOnRelease = !root.backgroundPopupGuard
    }
    onPositionChanged: function(mouse) {
      if (pressed && Math.max(Math.abs(mouse.x - pressPosition.x), Math.abs(mouse.y - pressPosition.y)) > drag.threshold)
        moved = true
    }
    onClicked: if (!moved && dismissOnRelease) root.closeButtonEdit()
  }

  // Below content: unused background dismisses only the editor, without intercepting controls.
  EditorDismissArea {
    objectName: "assignmentBackgroundDismiss"
    anchors.fill: parent
    z: -1
  }

  Column {
    id: headerColumn
    width: root.overviewWidth
    spacing: Style.spacing.controlGap
    PanelHero {
      width: parent.width
      title: root.model.t("plugin_name")
      meta: root.model.connectionStatusText
      foreground: root.fgColor
      fontFamily: root.fontFam
      iconOpacity: root.model.connected ? 1 : 0.45
      iconComponent: Component {
        Item {
          implicitWidth: Style.font.display
          implicitHeight: implicitWidth
          Image {
            id: heroIcon
            anchors.fill: parent
            source: Qt.resolvedUrl("assets/trackball.svg")
            sourceSize.width: Math.ceil(width * 4)
            sourceSize.height: Math.ceil(height * 4)
            smooth: true
            mipmap: true
            visible: false
          }
          MultiEffect {
            anchors.fill: parent
            source: heroIcon
            colorization: 1
            colorizationColor: root.fgColor
          }
        }
      }
      trailingControl: Component {
        ActionButton {
          text: root.model.effectiveLanguage.toUpperCase()
          iconText: "文"
          iconSize: Style.font.bodySmall
          focusable: true
          Accessible.name: root.model.t("language_title")
          tooltipText: root.model.t("language_title") + (root.model.language === "system" ? " · " + root.model.t("lang_system") : "")
          fontSize: Style.font.caption
          foreground: root.fgColor
          fontFamily: root.fontFam
          bordered: true
          selected: root.languageExpanded
          hasCursor: root.cursorActive && root.focusIndex === -2
          onClicked: { root.focusIndex = -2; root.languageExpanded = !root.languageExpanded }
        }
      }
    }

    Row {
      id: pageTabs
      objectName: "panelNavigation"
      width: parent.width
      spacing: Style.spacing.controlGap
      ErgoControl {
        width: (pageTabs.width - pageTabs.spacing * 2) / 3
        objectName: "page_buttons"
        caption: root.model.t("page_buttons")
        fontSize: Style.font.bodySmall
        fontFamily: root.fontFam
        foreground: root.fgColor
        bordered: false
        selected: root.panelPage === "buttons"
        hasCursor: root.cursorActive && root.focusIndex === -1 && selected
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.normalBorderWidth * (parent.selected ? 2 : 1)
          color: root.fgColor
          opacity: parent.selected ? 1 : 0.2
        }
        onClicked: root.showPage("buttons")
      }
      ErgoControl {
        width: (pageTabs.width - pageTabs.spacing * 2) / 3
        objectName: "page_pointer"
        caption: root.model.t("page_pointer")
        fontSize: Style.font.bodySmall
        fontFamily: root.fontFam
        foreground: root.fgColor
        bordered: false
        selected: root.panelPage === "pointer"
        hasCursor: root.cursorActive && root.focusIndex === -1 && selected
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.normalBorderWidth * (parent.selected ? 2 : 1)
          color: root.fgColor
          opacity: parent.selected ? 1 : 0.2
        }
        onClicked: root.showPage("pointer")
      }
      ErgoControl {
        width: (pageTabs.width - pageTabs.spacing * 2) / 3
        objectName: "page_device"
        caption: root.model.t("page_device")
        fontSize: Style.font.bodySmall
        fontFamily: root.fontFam
        foreground: root.fgColor
        bordered: false
        selected: root.panelPage === "device"
        hasCursor: root.cursorActive && root.focusIndex === -1 && selected
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Style.normalBorderWidth * (parent.selected ? 2 : 1)
          color: root.fgColor
          opacity: parent.selected ? 1 : 0.2
        }
        onClicked: root.showPage("device")
      }
    }
  }

  Flickable {
    id: viewport
    objectName: "overviewViewport"
    anchors.left: parent.left
    anchors.top: headerColumn.bottom
    anchors.topMargin: Style.spacing.controlGap
    anchors.bottom: parent.bottom
    width: root.overviewWidth
    contentWidth: width
    contentHeight: contentColumn.implicitHeight + Style.space(8)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      id: scrollBar
      parent: viewport
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      width: Style.space(3)
      policy: Controls.ScrollBar.AsNeeded
      contentItem: Rectangle {
        implicitWidth: Style.space(3)
        radius: width / 2
        color: root.dim
        opacity: scrollBar.active || scrollBar.hovered ? 0.6 : 0.2
      }
    }
  }

  EditorDismissArea {
    parent: viewport.contentItem
    width: viewport.width
    height: Math.max(viewport.height, viewport.contentHeight)
    z: -1
  }

  Column {
    id: contentColumn
    parent: viewport.contentItem
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.spacing.controlGap

    // Expandable Language Picker Section
    Column {
      visible: root.languageExpanded
      width: parent.width
      spacing: Style.space(6)

      PanelSectionHeader {
        width: parent.width
        text: root.model.t("language_title")
        foreground: root.fgColor
        fontFamily: root.fontFam
      }

      Grid {
        id: languageGrid
        width: parent.width
        columns: 3
        spacing: Style.spacing.labelGap

        readonly property real itemWidth: Math.floor((width - spacing * 2) / 3)

        Repeater {
          model: [
            { code: "system", label: root.model.t("lang_system") },
            { code: "en", label: "English" },
            { code: "zh", label: "简体中文" },
            { code: "es", label: "Español" },
            { code: "ru", label: "Русский" },
            { code: "pt", label: "Português" },
            { code: "fr", label: "Français" },
            { code: "de", label: "Deutsch" },
            { code: "ja", label: "日本語" },
            { code: "ko", label: "한국어" },
            { code: "it", label: "Italiano" }
          ]

          ActionButton {
            width: languageGrid.itemWidth
            text: modelData.label
            fontFamily: root.fontFam
            fontSize: Style.font.caption
            foreground: root.fgColor
            bordered: false
            focusable: true
            hasCursor: root.cursorActive && root.focusIndex === 10 + root.languageCodes.indexOf(modelData.code)
            selected: root.model.language === modelData.code
            active: root.model.language === modelData.code
            onClicked: {
              var code = modelData.code
              root.languageExpanded = false
              root.model.setLocale(code)
              root.focusIndex = -2
              root.forceActiveFocus()
            }
          }
        }
      }
    }

    Column {
      width: parent.width
      visible: root.model.configLoadFailed || root.model.sleepMonitorFailed || root.model.profileRetryId !== ""
        || (!root.editingButton && (root.model.configSaveFailed || root.model.settingsRecoveryFailed))
      spacing: Style.spacing.labelGap
      Repeater {
        model: [
          {show: root.model.configLoadFailed, key: "settings_load_error"},
          {show: !root.editingButton && root.model.configSaveFailed, key: "settings_save_error"},
          {show: !root.editingButton && root.model.settingsRecoveryFailed, key: "settings_apply_error"},
          {show: root.model.sleepMonitorFailed, key: "resume_monitor_error"}
        ]
        Text {
          required property var modelData
          visible: modelData.show
          width: parent.width
          text: root.model.t(modelData.key)
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.fgColor
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
          Accessible.role: Accessible.StaticText
          Accessible.name: text
        }
      }
      ActionButton {
        id: retrySettingsButton
        visible: root.model.profileRetryId !== "" || (!root.editingButton && (root.model.configSaveFailed || root.model.settingsRecoveryFailed))
        enabled: !root.model.settingsApplying && !root.model.configWriting && !root.model.profileBusy
        focusable: true
        hasCursor: root.cursorActive && root.focusIndex === -4
        text: root.model.t("settings_retry")
        foreground: root.fgColor
        fontFamily: root.fontFam
        fontSize: Style.font.caption
        onClicked: root.model.retrySettings()
      }
    }


    Column {
      width: parent.width
      spacing: Style.spacing.controlGap
      // The profile sets the context for all five physical assignments.
      ButtonProfilesPanel {
        id: profilesSection
        objectName: "buttonProfiles"
        width: parent.width
        model: root.model
        foreground: root.fgColor
        fontFamily: root.fontFam
        hasCursor: root.cursorActive && root.focusIndex === 7
        toolsParent: profileToolsHost
        onEditRequested: {
          root.editingButton = false
          root.isRecording = false
          root.languageExpanded = false
          root.panelPage = "buttons"
          Qt.callLater(function() { profileViewport.contentY = 0 })
        }
        onControlFocused: function(control) {
          Qt.callLater(function() {
            var area = control.mapToItem(profileViewport.contentItem, 0, 0)
            if (area.x >= 0) profileViewport.contentY = Math.max(0,
              Math.min(profileViewport.contentHeight - profileViewport.height,
                area.y < profileViewport.contentY ? area.y : Math.max(profileViewport.contentY,
                  area.y + control.height - profileViewport.height)))
          })
        }
        onLeaveRequested: function(direction) {
          root.forceActiveFocus()
          root.focusIndex = 7
          if (direction) root.stepFocus(direction)
        }
      }

      Rectangle {
        width: parent.width
        height: Style.normalBorderWidth
        color: root.fgColor
        opacity: 0.2
      }

      TrackballMap {
        id: btnSelectorRow
        enabled: !root.model.profileBusy
        width: parent.width
        height: implicitHeight
        foreground: root.fgColor
        background: Color.popups.background
        accent: root.bar && root.bar.accent !== undefined ? root.bar.accent : Color.accent
        fontFamily: root.fontFam
        labelSize: Style.font.body
        actionSize: Style.font.bodySmall
        gap: Style.spacing.labelGap
        padding: Style.space(6)
        borderWidth: Style.normalBorderWidth
        cornerRadius: Style.cornerRadius
        selectedButton: root.selectedButton
        hasCursor: root.editingButton || (root.cursorActive && root.focusIndex === 4)
        buttons: root.buttonList.map(function (button) {
          return { key: button.key, label: root.model.t(button.key === "back" ? "button_back_short" : button.key === "forward" ? "button_forward_short" : button.labelKey),
            action: root.model.actionLabel(root.model.getButtonAction(button.key), button.key),
            compact: root.model.getButtonAction(button.key) === "custom_shortcut" || root.model.getButtonAction(button.key) === "custom_command" }
        })
        onSelectionRequested: function (buttonKey) {
          if (root.backgroundPopupGuard) return
          if (root.editingButton && root.selectedButton === buttonKey) root.closeButtonEdit()
          else root.editButton(buttonKey)
        }
      }

    }

    // Bottom breathing margin
    Item {
      width: parent.width
      height: Style.space(4)
      implicitHeight: height
    }
  }

  Rectangle {
    x: root.overviewWidth + Style.spacing.controlGap
    y: pageTabs.y
    width: Style.normalBorderWidth
    height: Math.max(0, root.height - y)
    color: root.fgColor
    opacity: 0.2
  }

  // Explicit recovery remains available when BlueZ reports a stale connection.
  ErgoControl {
    id: connectButton
    objectName: "deviceRecovery"
    enabled: !root.model.recoveryStopping
      && (root.model.recoveryStage !== "" || (root.model.canStartRecovery && !root.model.isConnecting))
    hasCursor: root.cursorActive && root.focusIndex === -3
    Accessible.name: root.model.recoveryStage !== "" ? root.model.t("cancel_recovery")
      : (root.model.btDevice && root.model.btDevice.connected
          ? root.model.t("recover_connected_action") : root.model.t("connect_device"))
    visible: root.model.canRecover || root.model.recoveryBusy
    x: editorViewport.x
    y: 0
    width: editorViewport.width - Style.spacing.controlGap
    caption: root.model.recoveryStopping ? root.model.t("recovery_stopping")
      : root.model.recoveryStage !== "" ? root.model.t("cancel_recovery")
      : ("󰂯 " + (root.model.btDevice && root.model.btDevice.connected
          ? root.model.t("recover_connected_action") : root.model.t("connect_device")))
    detail: root.model.recoveryStage === "" && !root.model.recoveryStopping
      && root.model.recoveryResult !== "" ? root.model.t(root.model.recoveryResult) : ""
    fontSize: Style.font.bodySmall
    foreground: root.fgColor
    fontFamily: root.fontFam
    bordered: true
    onClicked: {
      if (root.model.recoveryStage !== "") root.model.cancelRecovery()
      else root.model.recoverDevice()
    }
  }


  Flickable {
    id: settingsViewport
    objectName: "settingsViewport"
    visible: root.panelPage !== "buttons"
    x: editorViewport.x
    y: editorViewport.y
    width: editorViewport.width
    height: editorViewport.height
    contentWidth: width
    contentHeight: settingsColumn.implicitHeight + Style.space(8)
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    clip: true
    Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
    Column {
      id: settingsColumn
      width: Math.max(0, settingsViewport.width - Style.spacing.controlGap)
      spacing: Style.spacing.controlGap
      Text {
        visible: !root.editingButton && root.model.recoveryResult !== "" && root.panelPage === "device"
        width: parent.width
        text: root.model.t(root.model.recoveryResult)
          + (root.model.recoveryScanNote ? "\n" + root.model.recoveryScanNote : "")
          + (root.model.recoveryOtherNote ? "\n" + root.model.recoveryOtherNote : "")
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.fgColor
        font.family: root.fontFam
        font.pixelSize: Style.font.caption
        Accessible.role: Accessible.StaticText
        Accessible.name: text
      }

      // Detailed device telemetry belongs to the Device page.
      Column {
        visible: root.panelPage === "device" && !root.editingButton
        width: parent.width
        spacing: Style.spacing.labelGap

        Item {
          width: parent.width
          height: batLabel.implicitHeight
          implicitHeight: height

          Text {
            id: batLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.model.batteryIcon + "  " + root.model.t("battery")
            color: root.fgColor
            font.family: root.fontFam
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.model.connected
              ? root.model.batteryLevelText
              : root.model.t("disconnected")
            color: root.model.connected ? root.fgColor : root.dim
            font.family: root.fontFam
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

      Text {
        width: parent.width
        visible: root.model.connected
        text: root.model.batteryReportText
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: root.fontFam
        font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width
        visible: root.model.batterySourceDifference !== ""
        text: root.model.batterySourceDifference
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: root.fontFam
        font.pixelSize: Style.font.caption
      }
      }




      Column {
        visible: root.panelPage === "pointer" && !root.editingButton
        width: parent.width
        spacing: Style.spacing.controlGap
        // ---------- Pointer & Hyprland Controls ----------
        PanelSectionHeader {
          text: root.model.t("pointer_settings")
          foreground: root.fgColor
          fontFamily: root.fontFam
        }

        Text {
          objectName: "pointerScope"
          width: parent.width
          text: root.model.t("pointer_scope")
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.dim
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
        }

        // Acceleration Profile (Adaptive vs Flat)
        Row {
          id: profileRow
          width: parent.width
          spacing: Style.spacing.controlGap

          readonly property real btnWidth: (width - spacing) / 2

          ErgoControl {
            width: profileRow.btnWidth
            objectName: "accelAdaptive"
            caption: root.model.t("accel_adaptive")
            fontSize: Style.font.bodySmall
            foreground: root.fgColor
            fontFamily: root.fontFam
            bordered: true
            selected: root.model.accelProfile === "adaptive"
            active: root.model.accelProfile === "adaptive"
            hasCursor: root.cursorActive && root.focusIndex === 0
            onClicked: {
              root.focusIndex = 0
              root.model.setAccelProfile("adaptive")
            }
          }

          ErgoControl {
            width: profileRow.btnWidth
            objectName: "accelFlat"
            caption: root.model.t("accel_flat")
            fontSize: Style.font.bodySmall
            foreground: root.fgColor
            fontFamily: root.fontFam
            bordered: true
            selected: root.model.accelProfile === "flat"
            active: root.model.accelProfile === "flat"
            hasCursor: root.cursorActive && root.focusIndex === 1
            onClicked: {
              root.focusIndex = 1
              root.model.setAccelProfile("flat")
            }
          }
        }

        // Sensitivity Slider
        Column {
          id: sensitivityColumn
          width: parent.width
          spacing: Style.space(3)

          Item {
            width: parent.width
            height: sensLabel.implicitHeight
            implicitHeight: height

            Text {
              id: sensLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.model.t("sensitivity") + (root.cursorActive && root.focusIndex === 2 ? " [◄ ►]" : "")
              color: root.cursorActive && root.focusIndex === 2 ? root.fgColor : root.dim
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              font.bold: root.cursorActive && root.focusIndex === 2
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: (root.model.sensitivity > 0 ? "+" : "") + root.model.sensitivity.toFixed(2)
              color: root.fgColor
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          PanelSlider {
            Accessible.role: Accessible.Slider
            Accessible.name: root.model.t("sensitivity")
            Accessible.description: root.model.sensitivity.toFixed(2)
            Accessible.onIncreaseAction: root.model.setSensitivity(root.model.sensitivity + 0.05)
            Accessible.onDecreaseAction: root.model.setSensitivity(root.model.sensitivity - 0.05)
            width: parent.width
            bar: root.bar
            minimum: -1.0
            maximum: 1.0
            step: 0.05
            value: root.model.sensitivity
            onMoved: function(val) {
              root.focusIndex = 2
              root.model.setSensitivity(val)
            }
            onReleased: function(val) {
              root.focusIndex = 2
              root.model.setSensitivity(val)
            }
          }
        }

        // Natural Scrolling Toggle Row
        Item {
          id: naturalRow
          objectName: "naturalScrollRow"
          Accessible.role: Accessible.CheckBox
          Accessible.name: root.model.t("natural_scroll")
          Accessible.checkable: true
          Accessible.checked: root.model.naturalScroll
          Accessible.onPressAction: root.model.setNaturalScroll(!root.model.naturalScroll)
          width: parent.width
          height: Math.max(Style.spacing.controlHeight, naturalLabel.implicitHeight + Style.space(12))
          implicitHeight: height

          Text {
            id: naturalLabel
            anchors.right: naturalSwitch.left
            anchors.rightMargin: Style.spacing.controlGap
            wrapMode: Text.Wrap
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.model.t("natural_scroll")
            color: root.fgColor
            font.family: root.fontFam
            font.pixelSize: Style.font.bodySmall
          }

          ToggleSwitch {
            id: naturalSwitch
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.model.naturalScroll
            interactive: false
            hasCursor: root.cursorActive && root.focusIndex === 3
            foreground: root.fgColor
            onToggled: root.model.setNaturalScroll(!root.model.naturalScroll)
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.focusIndex = 3
              root.model.setNaturalScroll(!root.model.naturalScroll)
            }
          }
        }

      }

      Column {
        visible: root.panelPage === "device" && !root.editingButton
        width: parent.width
        spacing: Style.spacing.controlGap
        // Auto-reconnect after startup and wake
        Item {
          id: autoReconnectRow
          objectName: "autoReconnectRow"
          Accessible.role: Accessible.CheckBox
          Accessible.name: root.model.t("auto_reconnect")
          Accessible.checkable: true
          Accessible.checked: root.model.autoReconnect
          Accessible.onPressAction: root.model.setAutoReconnect(!root.model.autoReconnect)
          width: parent.width
          height: Math.max(Style.spacing.controlHeight, autoRecLabel.implicitHeight + Style.space(12))
          implicitHeight: height

          Text {
            id: autoRecLabel
            anchors.right: autoRecSwitch.left
            anchors.rightMargin: Style.spacing.controlGap
            wrapMode: Text.Wrap
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.model.t("auto_reconnect")
            color: root.fgColor
            font.family: root.fontFam
            font.pixelSize: Style.font.bodySmall
          }

          ToggleSwitch {
            id: autoRecSwitch
            hasCursor: root.cursorActive && root.focusIndex === 5
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: root.model.autoReconnect
            interactive: false
            foreground: root.fgColor
            onToggled: root.model.setAutoReconnect(!root.model.autoReconnect)
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.model.setAutoReconnect(!root.model.autoReconnect)
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Style.normalBorderWidth
          color: root.fgColor
          opacity: 0.15
        }
        ErgoControl {
          id: advancedButton
          objectName: "deviceAdvanced"
          width: parent.width
          caption: root.model.t("advanced_settings")
          detail: root.advancedExpanded ? "" : root.model.lowLatencyBusy ? root.model.t("latency_busy")
            : root.model.lowLatencyFailed ? root.model.t("latency_error") : ""
          marker: root.advancedVisible ? "▴" : "▾"
          leftAlign: true
          selected: root.advancedVisible
          hasCursor: root.cursorActive && root.focusIndex === 6
          foreground: root.fgColor
          fontFamily: root.fontFam
          onClicked: { root.focusIndex = 6; root.advancedExpanded = !root.advancedExpanded }
        }

        // Controller-wide administrative action, disclosed separately from ordinary device controls.
        Column {
          id: latencyRow
          objectName: "adapterSettings"
          visible: root.advancedVisible
          width: parent.width
          spacing: Style.spacing.controlGap
          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.model.t("polling_rate")
            color: root.fgColor
            font.family: root.fontFam
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.model.t("low_latency_hint")
            color: root.dim
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
          }
          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.model.lowLatencyBusy ? root.model.t("latency_busy") : root.model.t("latency_" + root.model.lowLatencyState)
            color: root.fgColor
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: root.model.lowLatencyFailed
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.model.t("latency_error")
            color: root.fgColor
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
          }
          Text {
            visible: !root.model.lowLatencyHelperAvailable
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.model.t("latency_setup")
            color: root.dim
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
          }
          ActionButton {
            id: profileAction
            objectName: "adapterProfileAction"
            width: parent.width
            readonly property string actionLabel: root.model.t(root.model.lowLatencyLegacy ? "latency_cleanup" : root.model.lowLatencyCanRestore ? "latency_restore" : "latency_enable")
            implicitHeight: Math.max(Style.spacing.controlHeight, profileActionLabel.implicitHeight + verticalPadding * 2 + Style.normalBorderWidth * 2)
            Accessible.name: actionLabel
            enabled: root.model.lowLatencyHelperAvailable && !root.model.lowLatencyBusy
              && root.model.lowLatencyState !== "restart"
              && (root.model.lowLatencyCanRestore || root.model.lowLatencyLegacy || root.model.bluetoothAdapter !== "")
            hasCursor: root.cursorActive && root.focusIndex === 8
            foreground: root.fgColor
            fontFamily: root.fontFam
            fontSize: Style.font.bodySmall
            bordered: true
            onClicked: root.activateBluetoothProfile()
            Text {
              id: profileActionLabel
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: profileAction.horizontalPadding + Style.normalBorderWidth
              anchors.verticalCenter: parent.verticalCenter
              text: profileAction.actionLabel
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              horizontalAlignment: Text.AlignHCenter
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              color: root.fgColor
            }
          }
        }

      }


    }
  }

  Column {
    visible: root.panelPage === "buttons" && !root.editingButton && !profilesSection.toolsActive
    x: editorViewport.x
    y: editorViewport.y + Style.space(42)
    width: Math.max(0, editorViewport.width - Style.spacing.controlGap)
    spacing: Style.space(12)
    Text {
      objectName: "assignmentEmptyTitle"
      width: parent.width
      text: root.model.t("assignment_empty_title")
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.fgColor
      font.family: root.fontFam
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Text {
      width: parent.width
      text: root.model.t("assignment_empty_hint")
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.dim
      font.family: root.fontFam
      font.pixelSize: Style.font.bodySmall
    }
  }

  Flickable {
    id: profileViewport
    objectName: "profileToolsViewport"
    visible: root.panelPage === "buttons" && !root.editingButton && profilesSection.toolsActive
    x: editorViewport.x
    y: editorViewport.y
    width: editorViewport.width
    height: editorViewport.height
    contentWidth: width
    contentHeight: profileToolsHost.implicitHeight + Style.space(8)
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    clip: true
    Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
    Column {
      id: profileToolsHost
      width: Math.max(0, profileViewport.width - Style.spacing.controlGap)
      spacing: Style.space(12)
      Text {
        width: parent.width
        text: profilesSection.mode === "create" ? "+ " + root.model.t("profile_add")
          : root.model.t(profilesSection.mode === "rename" ? "profile_rename"
            : profilesSection.mode === "delete" ? "profile_delete" : "profile_manage")
        textFormat: Text.PlainText
        color: root.fgColor
        font.family: root.fontFam
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        width: parent.width
        visible: profilesSection.mode === "" || profilesSection.mode === "rename" || profilesSection.mode === "delete"
        text: root.model.t("profile_editing").replace("%1", root.model.activeProfileName)
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.dim
        font.family: root.fontFam
        font.pixelSize: Style.font.caption
      }
    }
  }

  Flickable {
    id: editorViewport
    objectName: "assignmentViewport"
    visible: root.editingButton
    x: root.overviewWidth + Style.spacing.controlGap + Style.space(16)
    y: Math.max(pageTabs.y, connectButton.visible ? connectButton.height + Style.spacing.controlGap : 0)
    width: Math.max(0, root.width - x - Style.spacing.controlGap)
    height: Math.max(0, root.height - y)
    contentWidth: width
    contentHeight: editorColumn.implicitHeight + Style.space(8)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

    EditorDismissArea {
      width: editorViewport.width
      height: Math.max(editorViewport.height, editorViewport.contentHeight)
      z: -2
    }

    // Protect the complete editor, including static text and gaps, from background dismissal.
    MouseArea {
      width: editorColumn.width
      height: editorColumn.height
      z: -1
      acceptedButtons: Qt.LeftButton
    }

    Column {
      id: editorColumn
      width: editorViewport.width - Style.spacing.controlGap
      spacing: Style.space(12)

      Row {
        width: parent.width
        spacing: Style.spacing.controlGap
        Text {
          width: Math.max(0, parent.width - editorBackButton.width - parent.spacing)
          anchors.verticalCenter: parent.verticalCenter
          text: root.model.t("profile_editing").replace("%1", root.model.activeProfileName)
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.dim
          font.family: root.fontFam
          font.pixelSize: Style.font.caption
        }
        ErgoControl {
          id: editorBackButton
          objectName: "closeAssignment"
          width: Math.min(implicitWidth, parent.width / 2)
          caption: root.model.t("close_editor")
          Accessible.name: root.model.t("close_editor_tooltip")
          tooltipText: root.model.t("close_editor_tooltip")
          bordered: true
          fontSize: Style.font.bodySmall
          fontFamily: root.fontFam
          foreground: root.fgColor
          onClicked: root.closeButtonEdit()
        }
      }
      // Selected button and action editor
      Rectangle {
        enabled: !root.model.profileBusy
        width: parent.width
        color: "transparent"
        height: activeCardCol.implicitHeight

        Column {
          id: activeCardCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(12)

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap
            Row {
              width: parent.width
              spacing: Style.spacing.controlGap
              Text {
                width: Math.max(0, parent.width - resetButton.width - parent.spacing)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.selectedButtonLabel()
                color: root.fgColor
                font.family: root.fontFam
                font.pixelSize: Style.font.body
                font.bold: true
                wrapMode: Text.Wrap
              }
              ErgoControl {
                id: resetButton
                width: Math.min(implicitWidth, parent.width / 2)
                caption: root.model.t("btn_reset_default")
                fontSize: Style.font.caption
                foreground: root.fgColor
                fontFamily: root.fontFam
                bordered: true
                onClicked: {
                  root.model.resetButtonToDefault(root.selectedButton)
                  root.finishButtonEdit()
                }
              }
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.model.t("assignment_label")
              color: root.dim
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }
            Text {
              objectName: "assignmentValue"
              width: parent.width
              textFormat: Text.PlainText
              text: root.model.actionLabel(root.selectedAction, root.selectedButton)
              color: root.fgColor
              font.family: root.fontFam
              font.pixelSize: Style.font.body
              font.bold: true
              wrapMode: Text.Wrap
              Accessible.role: Accessible.StaticText
              Accessible.name: text
            }
            Text {
              objectName: "assignmentStatus"
              width: parent.width
              textFormat: Text.PlainText
              text: root.model.t(root.assignmentStatusKey)
              font.bold: root.assignmentStatusKey !== "assignment_done" && root.assignmentStatusKey !== "assignment_unverified"
              color: root.fgColor
              font.family: root.fontFam
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
              Accessible.role: Accessible.StaticText
              Accessible.name: text
            }
            ErgoControl {
              objectName: "assignmentRetry"
              visible: root.model.configSaveFailed || root.model.settingsRecoveryFailed || root.model.profileRetryId !== ""
              enabled: !root.model.settingsPending && !root.model.configPending && !root.model.profileBusy
              caption: root.model.t("settings_retry")
              fontSize: Style.font.caption
              foreground: root.fgColor
              fontFamily: root.fontFam
              bordered: true
              onClicked: root.model.retrySettings()
            }
          }

          Rectangle {
            width: parent.width
            height: Style.normalBorderWidth
            color: root.fgColor
            opacity: 0.15
          }

          Text {
            objectName: "assignmentMethod"
            width: parent.width
            text: root.model.t("assignment_method")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.fgColor
            font.family: root.fontFam
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }

          // Mode Switcher (Presets | Record Shortcut | Command)
          Row {
            width: parent.width
            spacing: Style.space(6)

            readonly property real modeBtnWidth: (width - spacing * 2) / 3

            ErgoControl {
                focusable: true
              width: parent.modeBtnWidth
              caption: root.model.t("tab_presets")
              fontSize: Style.font.bodySmall
              foreground: root.fgColor
              fontFamily: root.fontFam
              bordered: false
              selected: root.setupMode === "presets"
              active: root.setupMode === "presets"
              onClicked: { root.setupMode = "presets"; root.isRecording = false }
            }

            ErgoControl {
                focusable: true
              width: parent.modeBtnWidth
              caption: root.model.t("tab_shortcut")
              fontSize: Style.font.bodySmall
              foreground: root.fgColor
              fontFamily: root.fontFam
              bordered: false
              selected: root.setupMode === "shortcut"
              active: root.setupMode === "shortcut"
              onClicked: { root.setupMode = "shortcut"; root.isRecording = false }
            }

            ErgoControl {
                focusable: true
              width: parent.modeBtnWidth
              caption: root.model.t("tab_command")
              fontSize: Style.font.bodySmall
              foreground: root.fgColor
              fontFamily: root.fontFam
              bordered: false
              selected: root.setupMode === "command"
              active: root.setupMode === "command"
              onClicked: { root.setupMode = "command"; root.isRecording = false }
            }
          }

          Text {
            objectName: "assignmentHint"
            width: parent.width
            textFormat: Text.PlainText
            text: root.model.t(root.setupMode === "presets" ? "assignment_preset_hint"
              : root.assignmentDraft ? "assignment_draft_hint"
              : root.selectedAction === "custom_" + root.setupMode ? "assignment_edit_hint" : "assignment_apply_hint")
            color: root.assignmentDraft ? root.fgColor : root.dim
            font.bold: root.assignmentDraft
            font.family: root.fontFam
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
          }

          ButtonActionPicker {
            id: actionPicker
            visible: root.setupMode === "presets"
            width: parent.width
            model: root.model
            foreground: root.fgColor
            fontFamily: root.fontFam
            selectedAction: root.selectedAction
            onChosen: function(action) {
              root.model.setButtonAction(root.selectedButton, action)
              root.finishButtonEdit()
            }
          }

          ActionButton {
            id: switchAllButton
            objectName: "profileSwitchAll"
            visible: root.selectedAction === "profile_next"
            width: parent.width
            readonly property string actionLabel: root.model.t("profile_switch_all")
            Accessible.name: actionLabel
            implicitHeight: Math.max(Style.spacing.controlHeight,
              switchAllLabel.implicitHeight + verticalPadding * 2 + Style.normalBorderWidth * 2)
            fontSize: Style.font.caption
            foreground: root.fgColor
            fontFamily: root.fontFam
            onClicked: {
              root.model.setProfileSwitchForAll(root.selectedButton)
              root.finishButtonEdit()
            }
            Text {
              id: switchAllLabel
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.margins: switchAllButton.horizontalPadding + Style.normalBorderWidth
              anchors.verticalCenter: parent.verticalCenter
              text: switchAllButton.actionLabel
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              horizontalAlignment: Text.AlignHCenter
              color: root.fgColor
              font.family: root.fontFam
              font.pixelSize: Style.font.caption
            }
          }

          // Mode 2: Custom Shortcut (Direct Input + System Chips + Key Recorder)
          Column {
            visible: root.setupMode === "shortcut"
            width: parent.width
            spacing: Style.space(6)

            // Direct editable text input field with Clear and Apply buttons
            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              TextField {
                id: shortcutInput
                objectName: "assignmentShortcut"
                maximumLength: 256
                font.family: root.fontFam
                width: parent.width
                font.pixelSize: Style.font.bodySmall
                placeholderText: root.model.t("shortcut_input_placeholder")
                Accessible.name: root.model.t("tab_shortcut")
                Accessible.description: root.model.t("assignment_edit_hint")
                text: root.model.getCustomShortcut(root.selectedButton)
                Keys.onTabPressed: function(event) {
                  if (root.isRecording) event.accepted = false
                  else { root.stepFocus(1); event.accepted = true }
                }
                Keys.onBacktabPressed: function(event) {
                  if (root.isRecording) event.accepted = false
                  else { root.stepFocus(-1); event.accepted = true }
                }
                onAccepted: {
                  root.model.setCustomShortcut(root.selectedButton, text)
                  root.finishButtonEdit()
                }
                Binding {
                  target: shortcutInput
                  property: "text"
                  value: root.model.getCustomShortcut(root.selectedButton)
                }

                Keys.onPressed: function(event) {
                  if (!root.isRecording) return

                  if (event.key === Qt.Key_Escape) {
                    root.isRecording = false
                    event.accepted = true
                    return
                  }

                  // Ignore solitary modifiers
                  if (event.key === Qt.Key_Control || event.key === Qt.Key_Shift ||
                      event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) {
                    event.accepted = true
                    return
                  }

                  var mods = []
                  if (event.modifiers & Qt.MetaModifier) mods.push("SUPER")
                  if (event.modifiers & Qt.ControlModifier) mods.push("CTRL")
                  if (event.modifiers & Qt.AltModifier) mods.push("ALT")
                  if (event.modifiers & Qt.ShiftModifier) mods.push("SHIFT")

                  var keyName = ""
                  if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                    keyName = String(event.key - Qt.Key_0)
                  } else if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) {
                    keyName = String.fromCharCode(event.key)
                  } else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) {
                    keyName = "F" + (event.key - Qt.Key_F1 + 1)
                  } else if (event.key === Qt.Key_Insert) {
                    keyName = "Insert"
                  } else if (event.key === Qt.Key_Delete) {
                    keyName = "Delete"
                  } else if (event.key === Qt.Key_Home) {
                    keyName = "Home"
                  } else if (event.key === Qt.Key_End) {
                    keyName = "End"
                  } else if (event.key === Qt.Key_PageUp) {
                    keyName = "PageUp"
                  } else if (event.key === Qt.Key_PageDown) {
                    keyName = "PageDown"
                  } else if (event.key === Qt.Key_Print) {
                    keyName = "Print"
                  } else if (event.key === Qt.Key_Pause) {
                    keyName = "Pause"
                  } else if (event.key === Qt.Key_Menu) {
                    keyName = "Menu"
                  } else if (event.key === Qt.Key_Space) {
                    keyName = "Space"
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    keyName = "Return"
                  } else if (event.key === Qt.Key_Tab) {
                    keyName = "Tab"
                  } else if (event.key === Qt.Key_Backtab) {
                    keyName = "Tab"
                    if (mods.indexOf("SHIFT") === -1) mods.push("SHIFT")
                  } else if (event.key === Qt.Key_Backspace) {
                    keyName = "BackSpace"
                  } else if (event.key === Qt.Key_Left) {
                    keyName = "Left"
                  } else if (event.key === Qt.Key_Right) {
                    keyName = "Right"
                  } else if (event.key === Qt.Key_Up) {
                    keyName = "Up"
                  } else if (event.key === Qt.Key_Down) {
                    keyName = "Down"
                  } else if (event.text && event.text.trim().length === 1) {
                    keyName = event.text.trim().toUpperCase()
                  }

                  if (keyName !== "") {
                    let full = (mods.length > 0 ? (mods.join(" + ") + " + ") : "") + keyName
                    shortcutInput.text = full
                    root.isRecording = false
                    event.accepted = true
                  }
                }
              }

              Row {
                width: parent.width
                spacing: Style.spacing.controlGap
              ErgoControl {
                focusable: true
                id: btnClear
                objectName: "assignmentClear"
                width: (parent.width - parent.spacing) / 2
                caption: root.model.t("clear_field")
                fontSize: Style.font.caption
                foreground: root.fgColor
                fontFamily: root.fontFam
                bordered: true
                onClicked: {
                  shortcutInput.text = ""
                }
              }

              ErgoControl {
                focusable: true
                id: btnApply
                objectName: "assignmentShortcutApply"
                width: (parent.width - parent.spacing) / 2
                caption: root.model.t("btn_apply")
                selected: true
                fontSize: Style.font.caption
                foreground: root.fgColor
                fontFamily: root.fontFam
                bordered: true
                onClicked: {
                  root.model.setCustomShortcut(root.selectedButton, shortcutInput.text.trim())
                  root.finishButtonEdit()
                }
              }
            }
            }

            ActionButton {
              width: parent.width
              focusable: true
              text: root.model.t(root.isRecording ? "recording_active" : "btn_record")
              fontSize: Style.font.bodySmall
              fontFamily: root.fontFam
              foreground: root.fgColor
              bordered: true
              selected: root.isRecording
              onClicked: {
                root.isRecording = !root.isRecording
                if (root.isRecording) shortcutInput.forceActiveFocus()
              }
            }

            // Row 1: Quick Modifier Chips (SUPER, CTRL, ALT, SHIFT)
            Row {
              id: modChipsRow
              width: parent.width
              spacing: Style.spacing.labelGap

              readonly property real modWidth: (width - spacing * 3) / 4

              Repeater {
                model: ["SUPER", "CTRL", "ALT", "SHIFT"]
                delegate: ActionButton {
                  required property string modelData
                  focusable: true
                  width: modChipsRow.modWidth
                  text: "+ " + modelData
                  fontSize: Style.font.caption
                  fontFamily: root.fontFam
                  foreground: root.fgColor
                  bordered: true
                  onClicked: root.addTokenToShortcut(modelData)
                }
              }
            }

            // Row 2: System & Navigation Chips (Insert, Delete, Home, End, PgUp, PgDn...)
            Flow {
              width: parent.width
              spacing: Style.spacing.labelGap

              Repeater {
                model: [
                  { id: "Insert", label: "Insert" },
                  { id: "Delete", label: "Delete" },
                  { id: "Home", label: "Home" },
                  { id: "End", label: "End" },
                  { id: "PageUp", label: "PgUp" },
                  { id: "PageDown", label: "PgDn" },
                  { id: "Tab", label: "Tab" },
                  { id: "Return", label: "Return" },
                  { id: "Space", label: "Space" },
                  { id: "Escape", label: "Esc" }
                ]
                delegate: ActionButton {
                  required property var modelData
                  focusable: true

                  text: modelData.label
                  fontSize: Style.font.caption
                  fontFamily: root.fontFam
                  foreground: root.fgColor
                  bordered: true
                  onClicked: root.addTokenToShortcut(modelData.id)
                }
              }
            }

            // Row 3: Workspace Digits 1..9 (fits 100% width, never overflows)
            Row {
              id: digitChipsRow
              width: parent.width
              spacing: Style.space(3)

              readonly property real digitWidth: (width - spacing * 8) / 9

              Repeater {
                model: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
                delegate: ActionButton {
                  required property string modelData
                  focusable: true
                  width: digitChipsRow.digitWidth
                  text: modelData
                  fontSize: Style.font.caption
                  fontFamily: root.fontFam
                  foreground: root.fgColor
                  bordered: true
                  onClicked: root.addTokenToShortcut(modelData)
                }
              }
            }

            // Row 4: Function Keys Toggle + Extra System Keys
            Row {
              width: parent.width
              spacing: Style.spacing.labelGap

              ActionButton {
                focusable: true
                text: "F1–F12" + (root.fKeysExpanded ? " ▴" : " ▾")
                fontSize: Style.font.caption
                foreground: root.fgColor
                fontFamily: root.fontFam
                bordered: true
                selected: root.fKeysExpanded
                active: root.fKeysExpanded
                onClicked: root.fKeysExpanded = !root.fKeysExpanded
              }

              Repeater {
                model: ["Print", "Pause", "Menu"]
                delegate: ActionButton {
                  required property string modelData
                  focusable: true

                  text: modelData
                  fontSize: Style.font.caption
                  fontFamily: root.fontFam
                  foreground: root.fgColor
                  bordered: true
                  onClicked: root.addTokenToShortcut(modelData)
                }
              }
            }

            // Expandable F1-F12 Grid
            Grid {
              visible: root.fKeysExpanded
              width: parent.width
              columns: 6
              spacing: Style.space(3)

              id: functionKeyGrid
              readonly property real fKeyWidth: (width - spacing * 5) / 6

              Repeater {
                model: ["F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]
                delegate: ActionButton {
                  required property string modelData
                  focusable: true
                  width: functionKeyGrid.fKeyWidth
                  text: modelData
                  fontSize: Style.font.caption
                  fontFamily: root.fontFam
                  foreground: root.fgColor
                  bordered: true
                  onClicked: root.addTokenToShortcut(modelData)
                }
              }
            }


          }

          // Mode 3: Direct Shell Command
          Column {
            visible: root.setupMode === "command"
            width: parent.width
            spacing: Style.spacing.labelGap

            TextField {
              id: cmdField
              objectName: "assignmentCommand"
              maximumLength: 2048
              font.family: root.fontFam
              width: parent.width
              font.pixelSize: Style.font.bodySmall
              placeholderText: root.model.t("custom_shortcut_placeholder")
              Accessible.name: root.model.t("tab_command")
              Accessible.description: root.model.t("assignment_edit_hint")
              text: root.model.getCustomCommand(root.selectedButton)
              Keys.onTabPressed: root.stepFocus(1)
              Keys.onBacktabPressed: root.stepFocus(-1)
              onAccepted: {
                root.model.setCustomCommand(root.selectedButton, text)
                root.finishButtonEdit()
              }
              Binding {
                target: cmdField
                property: "text"
                value: root.model.getCustomCommand(root.selectedButton)
              }
            }
            ErgoControl {
              objectName: "assignmentCommandApply"
                focusable: true
              caption: root.model.t("btn_apply")
              selected: true
              fontSize: Style.font.bodySmall
              fontFamily: root.fontFam
              foreground: root.fgColor
              bordered: true
              onClicked: {
                root.model.setCustomCommand(root.selectedButton, cmdField.text)
                root.finishButtonEdit()
              }
            }
          }
        }
      }
    }
  }

}
