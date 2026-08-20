import QtQuick
import Quickshell
import qs.Ui

BarWidget {
  id: root
  moduleName: "bibek.ytdl"

  readonly property var ytdlService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName)
    : null

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("ytdlService" in target) target.ytdlService = root.ytdlService
  }

  function syncService() {
    if (ytdlService && typeof ytdlService.configure === "function")
      ytdlService.configure(settings)
    injectPanel()
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: Qt.callLater(syncService)
  onSettingsChanged: Qt.callLater(syncService)
  onYtdlServiceChanged: Qt.callLater(syncService)
  Component.onCompleted: Qt.callLater(syncService)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.syncService)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: {
      if (!ytdlService) return "󰏔"
      if (!ytdlService.installed) return "󰏔"
      if (ytdlService.activeCount > 0) return " (" + ytdlService.activeCount + ")"
      return "󰗃"
    }
    hasVisualContent: text !== ""
    tooltipText: {
      if (!ytdlService || !ytdlService.installed) return "Install yt-dlp"
      if (ytdlService.activeCount > 0)
        return "yt-dlp - " + ytdlService.activeCount + " active download" + (ytdlService.activeCount > 1 ? "s" : "")
      return "yt-dlp - No active downloads"
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
