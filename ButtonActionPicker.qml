import QtQuick
import qs.Commons
import qs.Ui

// Category is navigation; the rows below it are choices for one physical button.
Column {
  id: root
  required property QtObject model
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string selectedAction: "default"
  property int categoryIndex: 4
  readonly property bool popupOpen: categoryPicker.popupOpen
  signal chosen(string action)
  spacing: Style.spacing.controlGap

  readonly property var categories: [
    {
      title: root.model.t("category_workspaces"),
      items: [
        { id: "workspace_next", label: root.model.t("action_workspace_next") },
        { id: "workspace_prev", label: root.model.t("action_workspace_prev") }
      ]
    },
    {
      title: root.model.t("category_windows"),
      items: [
        { id: "window_close", label: root.model.t("action_window_close") },
        { id: "window_float", label: root.model.t("action_window_float") },
        { id: "window_fullscreen", label: root.model.t("action_window_fullscreen") },
        { id: "window_next", label: root.model.t("action_window_next") }
      ]
    },
    {
      title: root.model.t("category_media"),
      items: [
        { id: "media_play_pause", label: root.model.t("action_media_play_pause") },
        { id: "mute", label: root.model.t("action_mute") },
        { id: "media_next", label: root.model.t("action_media_next") },
        { id: "media_prev", label: root.model.t("action_media_prev") }
      ]
    },
    {
      title: root.model.t("category_browser"),
      items: [
        { id: "tab_next", label: root.model.t("action_tab_next") },
        { id: "tab_prev", label: root.model.t("action_tab_prev") },
        { id: "browser_back", label: root.model.t("action_browser_back") },
        { id: "browser_forward", label: root.model.t("action_browser_forward") }
      ]
    },
    {
      title: root.model.t("category_system"),
      items: [
        { id: "overview", label: root.model.t("action_overview") },
        { id: "screenshot", label: root.model.t("action_screenshot") },
        { id: "profile_next", label: root.model.t("action_profile_next") },
        { id: "default", label: root.model.t("clear_binding") }
      ]
    }
  ]

  function categoryFor(action) {
    for (let i = 0; i < categories.length; ++i)
      if (categories[i].items.some(function(item) { return item.id === action })) return i
    return 4
  }
  onSelectedActionChanged: categoryIndex = categoryFor(selectedAction)
  Component.onCompleted: categoryIndex = categoryFor(selectedAction)

  Text {
    width: parent.width
    text: root.model.t("action_category")
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }
  Dropdown {
    id: categoryPicker
    objectName: "actionCategory"
    width: parent.width
    rowHeight: Math.max(Style.space(34), Style.spacing.controlHeight)
    showLabel: false
    foreground: root.foreground
    fontFamily: root.fontFamily
    value: String(root.categoryIndex)
    options: root.categories.map(function(group, index) { return {value: String(index), label: group.title} })
    Accessible.role: Accessible.ComboBox
    Accessible.name: root.model.t("action_category")
    onChanged: function(value) { root.categoryIndex = Number(value) }
  }
  Connections {
    target: root
    function onCategoryIndexChanged() { categoryPicker.value = String(root.categoryIndex); categoryPicker.close() }
  }
  Text {
    objectName: "availableActionsLabel"
    width: parent.width
    text: root.model.t("action_options")
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    wrapMode: Text.Wrap
  }
  Column {
    width: parent.width
    spacing: 0
    Repeater {
      model: root.categories[root.categoryIndex].items
      delegate: Column {
        required property var modelData
        width: parent.width
        spacing: 0
        ErgoControl {
          objectName: "action_" + modelData.id
          width: parent.width
          caption: modelData.label
          leftAlign: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          selected: root.selectedAction === modelData.id
          marker: selected ? "✓" : ""
          onClicked: root.chosen(modelData.id)
        }
        Rectangle {
          width: parent.width
          height: Style.normalBorderWidth
          color: root.foreground
          opacity: 0.15
        }
      }
    }
  }
}
