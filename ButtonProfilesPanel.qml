import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Profile management stays separate from the five-button editor.
Column {
  id: root
  required property QtObject model
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property bool hasCursor: false
  property string mode: ""
  property bool recording: false
  property bool managementExpanded: false
  // The consumer may host management tools beside the mouse; standalone use
  // keeps them below the selector.
  property Item toolsParent: null
  readonly property bool toolsActive: managementExpanded || mode !== ""
    || model.profileBusy || model.profileError !== ""
  readonly property bool popupOpen: picker.popupOpen
  readonly property bool ownsFocus: focusWithin(root) || focusWithin(tools)
  signal editRequested()
  signal controlFocused(Item control)
  signal leaveRequested(int direction)
  spacing: Style.spacing.controlGap

  component ProfileButton: ErgoControl {
    foreground: root.foreground
    fontFamily: root.fontFamily
    Keys.onTabPressed: function(event) { root.moveFocus(1); event.accepted = true }
    Keys.onBacktabPressed: function(event) { root.moveFocus(-1); event.accepted = true }
  }

  function focusWithin(item) {
    if (!item.visible) return false
    if (item.activeFocus) return true
    for (let i = 0; i < item.children.length; i++) if (root.focusWithin(item.children[i])) return true
    return false
  }

  function collectControls(item, result) {
    if (!item.visible || !item.enabled) return
    if (item.activeFocusOnTab) { result.push(item); return }
    for (let i = 0; i < item.children.length; i++) root.collectControls(item.children[i], result)
  }

  function focusFirst() {
    var controls = []
    root.collectControls(picker, controls)
    if (!controls.length) root.collectControls(root, controls)
    if (controls.length) controls[0].forceActiveFocus()
  }

  function moveFocus(direction) {
    var controls = []
    root.collectControls(root, controls)
    if (tools.parent !== root) root.collectControls(tools, controls)
    var index = controls.findIndex(function(item) { return item.activeFocus }) + direction
    if (index < 0 || index >= controls.length) root.leaveRequested(direction)
    else { controls[index].forceActiveFocus(); root.controlFocused(controls[index]) }
  }

  function reset() {
    root.mode = ""
    root.recording = false
    root.managementExpanded = false
    picker.close()
  }

  function edit(nextMode) {
    root.mode = nextMode
    root.recording = false
    root.editRequested()
    nameInput.text = nextMode === "rename" ? root.model.activeProfileName : ""
    shortcutField.text = root.model.profileShortcut
    if (nextMode === "create" || nextMode === "rename") nameInput.forceActiveFocus()
    else if (nextMode === "shortcut") shortcutField.forceActiveFocus()
  }

  function commitName() {
    if (root.mode === "create" ? root.model.createProfile(nameInput.text) : root.model.renameProfile(nameInput.text)) root.reset()
  }

  function commitShortcut() {
    root.recording = false
    if (root.model.setProfileShortcut(shortcutField.text)) root.reset()
  }

  function recordKey(event) {
    if (event.isAutoRepeat) return ""
    var modifiers = []
    if (event.modifiers & Qt.MetaModifier) modifiers.push("SUPER")
    if (event.modifiers & Qt.ControlModifier) modifiers.push("CTRL")
    if (event.modifiers & Qt.AltModifier) modifiers.push("ALT")
    if (event.modifiers & Qt.ShiftModifier) modifiers.push("SHIFT")
    var key = ""
    if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) key = String(event.key - Qt.Key_0)
    else if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z) key = String.fromCharCode(event.key)
    else if (event.key >= Qt.Key_F1 && event.key <= Qt.Key_F24) key = "F" + (event.key - Qt.Key_F1 + 1)
    else {
      let names = {}
      names[Qt.Key_Space] = "Space"; names[Qt.Key_Return] = "Return"; names[Qt.Key_Enter] = "Return"
      names[Qt.Key_Tab] = "Tab"; names[Qt.Key_Backtab] = "Tab"; names[Qt.Key_Backspace] = "BackSpace"
      names[Qt.Key_Insert] = "Insert"; names[Qt.Key_Delete] = "Delete"; names[Qt.Key_Home] = "Home"
      names[Qt.Key_End] = "End"; names[Qt.Key_PageUp] = "PageUp"; names[Qt.Key_PageDown] = "PageDown"
      names[Qt.Key_Left] = "Left"; names[Qt.Key_Right] = "Right"; names[Qt.Key_Up] = "Up"; names[Qt.Key_Down] = "Down"
      names[Qt.Key_Print] = "Print"; names[Qt.Key_Pause] = "Pause"; names[Qt.Key_Menu] = "Menu"
      key = names[event.key] || ""
    }
    return key ? modifiers.concat([key]).join(" + ") : ""
  }

  function handleEscape(event) {
    if (picker.popupOpen) picker.close()
    else if (root.recording) root.recording = false
    else { root.reset(); root.leaveRequested(0) }
    event.accepted = true
  }
  Keys.onEscapePressed: function(event) { root.handleEscape(event) }

  Connections {
    target: root.model
    function onActiveProfileIdChanged() { picker.value = root.model.activeProfileId; root.reset() }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.controlGap
    Text {
      width: Math.max(0, parent.width - managementButton.width - parent.spacing)
      anchors.verticalCenter: parent.verticalCenter
      text: root.model.t("profile_selector")
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      wrapMode: Text.Wrap
    }
    ProfileButton {
      id: managementButton
      objectName: "profileManage"
      width: Math.min(implicitWidth, parent.width / 2)
      caption: root.model.t("profile_manage")
      fontSize: Style.font.caption
      selected: root.managementExpanded
      enabled: root.model.configReadComplete && !root.model.profileBusy
      onClicked: {
        root.managementExpanded = !root.managementExpanded
        root.mode = ""
        root.recording = false
        if (root.managementExpanded) root.editRequested()
      }
    }
  }

  Row {
    width: parent.width
    spacing: Style.spacing.controlGap
    Dropdown {
      id: picker
      objectName: "profilePicker"
      width: Math.max(0, parent.width - addButton.width - parent.spacing)
      rowHeight: Math.max(Style.space(34), Style.spacing.controlHeight)
      showLabel: false
      foreground: root.foreground
      fontFamily: root.fontFamily
      hasCursor: root.hasCursor
      enabled: root.model.configReadComplete && !root.model.profileBusy
      value: root.model.activeProfileId
      options: root.model.buttonProfiles.map(function(item) { return {value: item.id, label: item.name} })
      Accessible.role: Accessible.ComboBox
      Accessible.name: root.model.t("profile_selector")
      Accessible.description: root.model.activeProfileName
      onChanged: function(value) {
        root.model.selectProfile(value)
        picker.value = root.model.activeProfileId
      }
      Keys.onTabPressed: function(event) { root.moveFocus(1); event.accepted = true }
      Keys.onBacktabPressed: function(event) { root.moveFocus(-1); event.accepted = true }
    }
    ProfileButton {
      id: addButton
      objectName: "profileAdd"
      width: Math.min(implicitWidth, parent.width * 0.4)
      height: Math.max(picker.height, implicitHeight)
      caption: "+ " + root.model.t("profile_add")
      bordered: true
      enabled: root.model.configReadComplete && !root.model.profileBusy && root.model.buttonProfiles.length < 32
      onClicked: root.edit("create")
    }
  }

  Column {
    id: tools
    objectName: "profileTools"
    parent: root.toolsParent || root
    width: parent.width
    spacing: Style.spacing.controlGap
    visible: root.toolsActive
    Keys.onEscapePressed: function(event) { root.handleEscape(event) }

  Column {
    visible: root.managementExpanded && root.mode === ""
    width: parent.width
    spacing: 0
    ProfileButton {
      objectName: "profileRename"
      width: parent.width
      leftAlign: true
      caption: root.model.t("profile_rename")
      enabled: root.model.configReadComplete && !root.model.profileBusy
      onClicked: root.edit("rename")
    }
    ProfileButton {
      objectName: "profileDelete"
      width: parent.width
      leftAlign: true
      caption: root.model.t("profile_delete")
      enabled: !root.model.profileBusy && root.model.buttonProfiles.length > 1
      onClicked: root.edit("delete")
    }
  }

  ProfileButton {
    objectName: "profileShortcut"
    visible: root.managementExpanded && root.mode === ""
    width: parent.width
    leftAlign: true
    bordered: true
    caption: root.model.t("profile_shortcut")
    detail: root.model.profileShortcut || root.model.t("profile_shortcut_unset")
    enabled: root.model.configReadComplete && !root.model.profileBusy
    onClicked: root.edit("shortcut")
  }

  Column {
    width: parent.width
    visible: root.mode !== ""
    spacing: Style.spacing.labelGap
    enabled: !root.model.profileBusy
    Text {
      visible: root.mode === "shortcut"
      width: parent.width
      text: root.model.t("profile_shortcut")
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      wrapMode: Text.Wrap
    }
    Text {
      width: parent.width
      text: root.model.t(root.mode === "create" ? "profile_create_hint" : root.mode === "rename"
        ? "profile_name" : root.mode === "delete" ? "profile_delete_confirm" : "profile_shortcut_hint")
        .replace("%1", root.model.activeProfileName)
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.Wrap
    }
    TextField {
      id: nameInput
      objectName: "profileNameInput"
      width: parent.width
      visible: root.mode === "create" || root.mode === "rename"
      maximumLength: 80
      foreground: root.foreground
      font.family: root.fontFamily
      placeholderText: root.model.t("profile_name")
      Accessible.name: placeholderText
      onAccepted: root.commitName()
      Keys.onTabPressed: function(event) { root.moveFocus(1); event.accepted = true }
      Keys.onBacktabPressed: function(event) { root.moveFocus(-1); event.accepted = true }
    }
    TextField {
      id: shortcutField
      objectName: "profileShortcutInput"
      width: parent.width
      visible: root.mode === "shortcut"
      maximumLength: 256
      foreground: root.foreground
      font.family: root.fontFamily
      placeholderText: root.model.t("shortcut_input_placeholder")
      Accessible.name: root.model.t("profile_shortcut")
      onAccepted: root.commitShortcut()
      Keys.onPressed: function(event) {
        if (!root.recording) return
        if (event.key === Qt.Key_Escape) root.recording = false
        else {
          let key = root.recordKey(event)
          if (key) { text = key; root.recording = false }
        }
        event.accepted = true
      }
      Keys.onTabPressed: function(event) {
        if (root.recording) { text = root.recordKey(event); root.recording = false }
        else root.moveFocus(1)
        event.accepted = true
      }
      Keys.onBacktabPressed: function(event) {
        if (root.recording) { text = root.recordKey(event); root.recording = false }
        else root.moveFocus(-1)
        event.accepted = true
      }
    }
    Row {
      visible: root.mode === "shortcut"
      width: parent.width
      spacing: Style.spacing.controlGap
      ProfileButton {
        objectName: "profileRecord"
        width: (parent.width - parent.spacing) / 2
        caption: root.model.t(root.recording ? "recording_active" : "btn_record")
        bordered: true
        onClicked: { root.recording = !root.recording; if (root.recording) shortcutField.forceActiveFocus() }
      }
      ProfileButton {
        objectName: "profileClear"
        width: (parent.width - parent.spacing) / 2
        caption: root.model.t("btn_clear")
        onClicked: { shortcutField.text = ""; root.recording = false }
      }
    }
    Row {
      width: parent.width
      spacing: Style.spacing.controlGap
      ProfileButton {
        objectName: "profileCancel"
        width: (parent.width - parent.spacing) / 2
        caption: root.model.t("profile_cancel")
        onClicked: root.reset()
      }
      ProfileButton {
        objectName: "profileApply"
        width: (parent.width - parent.spacing) / 2
        caption: root.model.t(root.mode === "delete" ? "profile_delete" : "btn_apply")
        bordered: true
        selected: true
        onClicked: {
          if (root.mode === "delete") { if (root.model.deleteProfile()) root.reset() }
          else if (root.mode === "shortcut") root.commitShortcut()
          else root.commitName()
        }
      }
    }
  }

  Text {
    width: parent.width
    visible: root.model.profileBusy || root.model.profileError !== ""
    text: root.model.t(root.model.profileBusy ? "profile_applying" : root.model.profileError)
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
    Accessible.role: Accessible.StaticText
    Accessible.name: text
  }
  }
}
