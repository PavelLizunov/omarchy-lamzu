import QtQuick
import QtQuick.Shapes

// Presentation only: selecting a hotspot never writes a device setting.
// Theme metrics are supplied by the host, keeping this component device-independent.
Item {
  id: root
  required property var buttons
  required property color foreground
  required property color background
  required property color accent
  required property string fontFamily
  required property real labelSize
  required property real actionSize
  required property real gap
  required property real padding
  required property real borderWidth
  required property real cornerRadius
  property string selectedButton: "back"
  property bool hasCursor: false
  readonly property Item selectedControl: selectedButton === "forward" ? forwardCallout
    : selectedButton === "middle" ? middleCallout : backCallout
  signal selectionRequested(string buttonKey)
  signal clicked(string buttonKey)

  implicitHeight: Math.max(device.y + device.height, leftLabels.y + leftLabels.height) + gap

  // Coordinates refer to the device item coordinate space.
  readonly property var locations: ({
    forward: { x: 0.296, y: 0.400, w: 0.026, h: 0.110 },
    back: { x: 0.298, y: 0.535, w: 0.026, h: 0.110 },
    middle: { x: 0.495, y: 0.230, w: 0.055, h: 0.105 }
  })

  function buttonInfo(key) {
    for (let i = 0; i < buttons.length; ++i) {
      if (buttons[i].key === key) return buttons[i]
    }
    return { key: key, label: "", action: "" }
  }

  function selectButton(key) {
    if (locations[key] && buttons.some(function (button) { return button.key === key })) {
      selectionRequested(key)
      clicked(key)
    }
  }

  component Callout: FocusScope {
    id: callout
    required property string buttonKey
    required property bool leftSide
    property bool topSide: false
    readonly property real diagramX: x + (parent === root ? 0 : parent.x)
    readonly property real diagramY: y + (parent === root ? 0 : parent.y)
    readonly property var info: root.buttonInfo(buttonKey)
    readonly property var location: root.locations[buttonKey]
    readonly property bool selected: root.selectedButton === buttonKey
    readonly property color ink: selected ? root.accent : root.foreground
    readonly property point point: location
      ? Qt.point(device.x + location.x * device.width, device.y + location.y * device.height)
      : Qt.point(0, 0)
    readonly property point origin: Qt.point(
      diagramX + (topSide ? width / 2 : leftSide ? width : 0),
      diagramY + (topSide ? height : height / 2)
    )
    objectName: "callout_" + buttonKey
    implicitHeight: labels.implicitHeight + root.padding * 2
    height: implicitHeight
    activeFocusOnTab: true
    Accessible.role: Accessible.RadioButton
    Accessible.name: info.label
    Accessible.description: info.action
    Accessible.checked: selected
    Accessible.onPressAction: root.selectButton(buttonKey)
    Keys.onReturnPressed: root.selectButton(buttonKey)
    Keys.onEnterPressed: root.selectButton(buttonKey)
    Keys.onSpacePressed: root.selectButton(buttonKey)

    Shape {
      preferredRendererType: Shape.CurveRenderer
      // Paint in the diagram coordinate space, beneath the label and hotspot.
      x: -callout.diagramX
      y: -callout.diagramY
      width: root.width
      height: root.height
      ShapePath {
        strokeColor: callout.ink
        strokeWidth: root.borderWidth
        fillColor: "transparent"
        startX: callout.origin.x
        startY: callout.origin.y
        PathLine {
          x: callout.origin.x + (callout.topSide ? 0 : callout.leftSide ? root.gap : -root.gap)
          y: callout.origin.y + (callout.topSide ? root.gap : 0)
        }
        PathLine { x: callout.point.x; y: callout.point.y }
      }
      opacity: callout.selected ? 1 : 0.55
    }
    Rectangle {
      anchors.fill: parent
      radius: root.cornerRadius
      color: root.background
      border.width: callout.activeFocus || (callout.selected && root.hasCursor) ? root.borderWidth * 2 : root.borderWidth
      border.color: callout.selected || callout.activeFocus ? root.accent
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: root.accent
        opacity: callout.selected ? 0.13 : calloutMouse.containsMouse ? 0.06 : 0
      }
    }
    Column {
      id: labels
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: root.padding
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.gap / 2
      Text {
        objectName: "label_" + callout.buttonKey
        width: parent.width
        textFormat: Text.PlainText
        text: callout.info.label
        font.family: root.fontFamily
        font.pixelSize: root.labelSize
        font.bold: callout.selected
        color: callout.ink
        wrapMode: Text.Wrap
      }
      Text {
        objectName: "action_" + callout.buttonKey
        width: parent.width
        textFormat: Text.PlainText
        text: callout.info.action
        font.family: root.fontFamily
        font.pixelSize: root.actionSize
        color: root.foreground
        opacity: 0.85
        maximumLineCount: callout.info.compact === true ? 2 : 4
        elide: Text.ElideRight
        wrapMode: Text.Wrap
      }
    }
    MouseArea {
      id: calloutMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        callout.forceActiveFocus()
        root.selectButton(callout.buttonKey)
      }
    }
  }

  Callout {
    id: middleCallout
    x: device.x + (device.width - width) / 2
    width: Math.min(root.width * 0.44, 160)
    buttonKey: "middle"
    leftSide: false
    topSide: true
  }

  Column {
    id: leftLabels
    y: device.y + device.height * 0.30
    width: root.width * 0.23
    spacing: root.gap * 3
    Callout {
      id: forwardCallout
      width: parent.width
      buttonKey: "forward"
      leftSide: true
    }
    Callout {
      id: backCallout
      width: parent.width
      buttonKey: "back"
      leftSide: true
    }
  }

  Image {
    id: device
    objectName: "mouseIllustration"
    x: (root.width - width) / 2
    y: middleCallout.height + root.gap
    width: root.width * 1.20
    height: width
    source: Qt.resolvedUrl("assets/thorn-photo.png")
    asynchronous: true
    sourceSize.width: Math.min(1600, Math.ceil(width * 3))
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    z: -1
  }

  // Interactive Hotspots
  Repeater {
    model: root.buttons
    delegate: Rectangle {
      id: hotspot
      required property var modelData
      readonly property var location: root.locations[modelData.key]
      readonly property bool selected: root.selectedButton === modelData.key
      objectName: "hotspot_" + modelData.key
      x: location ? (device.x + device.width * location.x - width / 2) : 0
      y: location ? (device.y + device.height * location.y - height / 2) : 0
      width: location ? Math.max(root.borderWidth * 8, device.width * location.w) : 0
      height: location ? Math.max(root.borderWidth * 12, device.height * location.h) : 0
      radius: width / 2
      color: selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : "transparent"
      border.width: selected || hotspotMouse.containsMouse ? root.borderWidth * 2 : 0
      border.color: root.accent
      Accessible.ignored: true // The corresponding callout supplies the accessible control.

      Rectangle {
        anchors.centerIn: parent
        width: root.borderWidth * 4
        height: width
        radius: width / 2
        color: hotspot.selected ? root.accent : root.foreground
      }

      MouseArea {
        id: hotspotMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.selectButton(hotspot.modelData.key)
      }
    }
  }
}
