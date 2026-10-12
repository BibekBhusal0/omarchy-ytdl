import QtQuick
import qs.Commons
import qs.Ui

// Single-line plain-text editor on TextEdit: unlike TextInput, its clipboard
// check reads offered formats only, never clipboard content. Pastes arrive
// solely through pasteRequested with the owner's capped helper.
FocusScope {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property color selectionTint: Style.selectionFillFor(foreground, accent)
  property bool hasCursor: false
  property string placeholderText: ""
  property alias text: field.text
  property alias cursorPosition: field.cursorPosition
  property alias font: field.font
  readonly property bool hovered: hoverMouse.containsMouse

  signal accepted
  signal pasteRequested(bool primary)

  function clearFocus() {
    field.focus = false;
  }

  readonly property bool _focused: activeFocus
  readonly property bool _hot: hovered || hasCursor
  readonly property var _borderSpec: Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

  implicitHeight: field.contentHeight + Style.spacing.inputPaddingY * 2 + Border.top(_borderSpec) + Border.bottom(_borderSpec)

  BorderSurface {
    anchors.fill: parent
    color: Style.controlFill(root._focused, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Style.cornerRadius
  }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.controlPaddingX + Border.left(root._borderSpec)
    anchors.rightMargin: Style.spacing.controlPaddingX + Border.right(root._borderSpec)
    anchors.topMargin: Style.spacing.inputPaddingY + Border.top(root._borderSpec)
    anchors.bottomMargin: Style.spacing.inputPaddingY + Border.bottom(root._borderSpec)
    clip: true
    interactive: false
    contentWidth: field.width
    contentHeight: field.height

    TextEdit {
      id: field
      width: Math.max(flick.width, implicitWidth)
      height: Math.max(flick.height, contentHeight)
      verticalAlignment: TextEdit.AlignVCenter
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      color: root.foreground
      selectionColor: root.selectionTint
      selectedTextColor: root.foreground
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.NoWrap
      selectByMouse: true
      focus: true
      cursorVisible: activeFocus

      onCursorRectangleChanged: {
        if (field.cursorRectangle.x < flick.contentX)
          flick.contentX = field.cursorRectangle.x;
        else if (field.cursorRectangle.x + field.cursorRectangle.width > flick.contentX + flick.width)
          flick.contentX = field.cursorRectangle.x + field.cursorRectangle.width - flick.width;
      }

      Keys.onPressed: function (event) {
        if ((event.modifiers & Qt.ControlModifier) !== 0 && event.key === Qt.Key_V) {
          event.accepted = true;
          root.pasteRequested(false);
          return;
        }
        if ((event.modifiers & Qt.ShiftModifier) !== 0 && event.key === Qt.Key_Insert) {
          event.accepted = true;
          root.pasteRequested(false);
          return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          event.accepted = true;
          root.accepted();
          return;
        }
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          event.accepted = true;
          var next = field.nextItemInFocusChain(event.key === Qt.Key_Tab);
          if (next)
            next.focus = true;
          return;
        }
      }
    }
  }

  Text {
    anchors.fill: flick
    anchors.leftMargin: flick.anchors.leftMargin
    verticalAlignment: Text.AlignVCenter
    text: root.placeholderText
    font: field.font
    color: Qt.darker(root.foreground, 1.6)
    visible: field.text.length === 0
  }

  MouseArea {
    id: hoverMouse
    anchors.fill: parent
    acceptedButtons: Qt.MiddleButton
    hoverEnabled: true
    onClicked: root.pasteRequested(true)
  }
}
