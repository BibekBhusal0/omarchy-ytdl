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
      var total = ytdlService.activeCount + ytdlService.queuedCount
      if (total > 0) return " (" + total + ")"
      return "󰗃"
    }
    hasVisualContent: text !== ""
    tooltipText: {
      if (!ytdlService || !ytdlService.installed) return "Install yt-dlp"
      var parts = []
      if (ytdlService.activeCount > 0)
        parts.push(ytdlService.activeCount + " active")
      if (ytdlService.queuedCount > 0)
        parts.push(ytdlService.queuedCount + " queued")
      if (parts.length > 0)
        return "yt-dlp - " + parts.join(", ")
      return "yt-dlp - No active downloads"
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.RightButton) {
        if (ytdlService) ytdlService.autoDownload()
      }
      else if (buttonCode === Qt.MiddleButton) {
        if (ytdlService) ytdlService.cancelAll()
      }
    }
  }
}
