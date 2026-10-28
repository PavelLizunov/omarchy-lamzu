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
    : selectedButton === "middle" ? middleCallout : selectedButton === "tiltLeft" ? leftCallout
    : selectedButton === "tiltRight" ? rightCallout : backCallout
  signal selectionRequested(string buttonKey)

  implicitHeight: Math.max(device.y + device.height, leftLabels.y + leftLabels.height,
                           rightLabels.y + rightLabels.height) + gap

  // Coordinates refer to the bundled 1024 × 1536 cutout, including its transparent margins.
  readonly property var locations: ({
    forward: { x: 0.300, y: 0.147, w: 0.043, h: 0.085 },
    back: { x: 0.302, y: 0.254, w: 0.043, h: 0.089 },
    middle: { x: 0.550, y: 0.229, w: 0.090, h: 0.117 },
    tiltLeft: { x: 0.452, y: 0.229, w: 0.055, h: 0.045 },
    tiltRight: { x: 0.649, y: 0.229, w: 0.055, h: 0.045 }
  })

  function buttonInfo(key) {
    for (let i = 0; i < buttons.length; ++i) {
      if (buttons[i].key === key) return buttons[i]
    }
    return { key: key, label: "", action: "" }
  }

  function selectButton(key) {
    if (locations[key] && buttons.some(function (button) { return button.key === key }))
      selectionRequested(key)
  }

  Image {
    id: device
    objectName: "trackballIllustration"
    x: (root.width - width) / 2
    y: middleCallout.height + root.gap * 2
    width: root.width * 0.70
    height: width * 1.5
    source: Qt.resolvedUrl("assets/trackball-map.png")
    asynchronous: true
    sourceSize.width: Math.min(1024, Math.ceil(width * 3))
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
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
    readonly property point point: Qt.point(device.x + location.x * device.width,
                                            device.y + location.y * device.height)
    readonly property point origin: Qt.point(diagramX + (topSide ? width / 2 : leftSide ? width : 0), diagramY + (topSide ? height : height / 2))
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
        PathLine { x: callout.origin.x + (callout.topSide ? 0 : callout.leftSide ? root.gap : -root.gap); y: callout.origin.y + (callout.topSide ? root.gap : 0) }
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
    x: (root.width - width) / 2
    width: root.width * 0.40
    buttonKey: "middle"
    leftSide: false
    topSide: true
  }
  Column {
    id: leftLabels
    y: middleCallout.height + root.gap * 2
    width: root.width * 0.30
    spacing: root.gap * 3
    Callout {
      id: forwardCallout
      width: parent.width
      height: Math.max(implicitHeight, leftCallout.implicitHeight)
      buttonKey: "forward"
      leftSide: true
    }
    Callout {
      id: backCallout
      width: parent.width
      height: Math.max(implicitHeight, rightCallout.implicitHeight)
      buttonKey: "back"
      leftSide: true
    }
  }
  Column {
    id: rightLabels
    x: root.width - width
    y: leftLabels.y
    width: leftLabels.width
    spacing: leftLabels.spacing
    Callout {
      id: leftCallout
      width: parent.width
      height: forwardCallout.height
      buttonKey: "tiltLeft"
      leftSide: false
    }
    Callout {
      id: rightCallout
      width: parent.width
      height: backCallout.height
      buttonKey: "tiltRight"
      leftSide: false
    }
  }

  Repeater {
    model: root.buttons
    delegate: Rectangle {
      id: hotspot
      required property var modelData
      readonly property var location: root.locations[modelData.key]
      readonly property bool selected: root.selectedButton === modelData.key
      readonly property bool tilt: modelData.key === "tiltLeft" || modelData.key === "tiltRight"
      objectName: "hotspot_" + modelData.key
      x: device.x + device.width * location.x - width / 2
      y: device.y + device.height * location.y - height / 2
      width: Math.max(root.borderWidth * 8, device.width * location.w)
      height: Math.max(root.borderWidth * 12, device.height * location.h)
      radius: width / 2
      color: selected ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : "transparent"
      border.width: selected || hotspotMouse.containsMouse ? root.borderWidth * 2 : 0
      border.color: root.accent
      Accessible.ignored: true // The corresponding callout supplies the accessible control.
      Text {
        anchors.centerIn: parent
        visible: hotspot.tilt
        text: hotspot.modelData.key === "tiltLeft" ? "‹" : "›"
        color: hotspot.selected ? root.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.labelSize * 1.4
      }
      Rectangle {
        visible: !hotspot.tilt
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
