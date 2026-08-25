import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "bibek.ytdl"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var ytdlService: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: Color.popups.text
  readonly property color activeColor: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string inputUrl: ""
  property string clipboardUrl: ""

  property bool settingsPanelVisible: false

  // Keyboard cursor model: focusSection × selectedIndex.
  property string focusSection: "input"
  property int selectedIndex: 0
  property bool cursorActive: false

  // Hover state: separate from keyboard cursor for visual feedback.
  property string hoverSection: ""
  property int hoverIndex: -1

  readonly property bool installed: ytdlService ? ytdlService.installed : false
  readonly property int activeCount: ytdlService ? ytdlService.activeCount : 0
  readonly property var activeDownloads: ytdlService ? filterActive(ytdlService.downloads) : []
  readonly property int queuedCount: ytdlService ? ytdlService.queuedCount : 0
  readonly property var queuedDownloads: ytdlService ? filterQueued(ytdlService.downloads) : []
  readonly property int historyCount: ytdlService ? ytdlService.historyCount : 0
  readonly property var historyItems: ytdlService ? ytdlService.history : []
  readonly property bool playlistSectionVisible: ytdlService && ytdlService.playlistInfoUrl !== ""
  readonly property bool detectedSectionVisible: ytdlService && ytdlService.detectedUrl !== ""
  readonly property bool hasRetryableItems: {
    for (var i = 0; i < root.historyItems.length; i++) {
      if (root.historyItems[i].status === "error" || root.historyItems[i].status === "cancelled") return true
    }
    return false
  }

  // Shown on the settings button instead of a bare gear icon so the current
  // quality/format choice is visible at a glance.
  readonly property string selectionSummary: {
    if (!ytdlService) return ""
    var t = ytdlService.defaultDownloadType
    var q = ytdlService.selectedQuality
    if (t === "audio") return "Audio"
    if (t === "both") return q + " · Audio"
    return q
  }

  property bool _serviceWired: false

  // The bar widget injects ytdlService after both components load, so IPC
  // requests reach the panel through these service signals.
  function wireService() {
    if (root._serviceWired || !ytdlService) return
    root._serviceWired = true
    ytdlService.openPanelRequested.connect(function() {
      if (!root.opened) root.open()
    })
    ytdlService.openSettingsRequested.connect(function(openIt) {
      if (!root.opened) root.open()
      if (openIt && !root.settingsPanelVisible) root.openSettings()
      else if (!openIt && root.settingsPanelVisible) root.closeSettings()
    })
  }

  onInputUrlChanged: {
    if (inputUrl && urlInput.text !== inputUrl)
      urlInput.text = inputUrl
  }

  onOpenedChanged: {
    if (root.opened) {
      root.settingsPanelVisible = false;
      if (ytdlService) ytdlService.pruneMissing();
    }
  }

  function filterActive(list) {
    var r = []
    for (var i = 0; i < list.length; i++)
      if (list[i].status === "downloading")
        r.push(list[i])
    return r
  }

  function filterQueued(list) {
    var r = []
    for (var i = 0; i < list.length; i++)
      if (list[i].status === "queued")
        r.push(list[i])
    return r
  }

  function open() {
    root.focusSection = "input"
    root.selectedIndex = 0
    root.cursorActive = false
    root.settingsPanelVisible = false
    controller.show()
    if (ytdlService) {
      ytdlService.checkInstallation()
      root.pasteClipboard()
      ytdlService.detectYouTube()
    }
  }

  function close() {
    root.hoverSection = ""
    root.hoverIndex = -1
    controller.hide()
  }

  // Handle panel toggle: when the widget on the bar is clicked, it opens/closes.
  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function pasteClipboard() {
    if (!ytdlService) return
    ytdlService.checkClipboard(function(url) {
      if (!url || ytdlService.isUrlBusy(url)) {
        root.clipboardUrl = ""
        return
      }
      root.clipboardUrl = url
      root.inputUrl = url
      if (urlInput.text !== url) urlInput.text = url
    })
  }

  function submitUrl() {
    if (!ytdlService || !inputUrl) return
    ytdlService.startDownload(inputUrl, ytdlService.selectedQuality, false, "", ytdlService.defaultDownloadType)
    inputUrl = ""
    urlInput.text = ""
  }

  function openSettings() {
    root.settingsPanelVisible = true
    root.focusSection = "settings"
    root.selectedIndex = 0
    root.cursorActive = true
  }

  function closeSettings() {
    root.settingsPanelVisible = false
    root.focusSection = "input"
    root.selectedIndex = 1
    root.cursorActive = true
  }

  function focusUrlField() {
    if (root.settingsPanelVisible) return
    root.focusSection = "input"
    root.selectedIndex = 0
    root.cursorActive = true
    if (urlInput) urlInput.forceActiveFocus()
  }

  // Returns focus from text field to the main key catcher.
  function focusPanel() {
    keyCatcher.forceActiveFocus()
    if (urlInput) urlInput.focus = false
  }

  function sectionList() {
    if (root.settingsPanelVisible) {
      return ["settings"]
    }
    var s = []
    if (!root.installed && !(ytdlService && ytdlService.checkingInstallation)) s.push("install")
    if (root.installed) s.push("input")
    if (root.installed && root.detectedSectionVisible) s.push("detected")
    if (root.installed && root.playlistSectionVisible) s.push("playlist")
    if (root.installed && root.activeCount > 0) s.push("downloads")
    if (root.installed && root.queuedCount > 0) s.push("queue")
    if (root.installed && root.historyCount > 0) s.push("history")
    return s
  }

  function sectionCount(name) {
    if (name === "settings") {
      return settingsPanelLoader.item ? settingsPanelLoader.item.visibleItems.length : 0
    }
    if (name === "install") return 1
    if (name === "input") return 3
    if (name === "detected") return 1
    if (name === "playlist") return 1
    if (name === "downloads") return root.activeCount + (root.activeCount > 0 ? 1 : 0)
    if (name === "queue") return root.queuedCount + (root.queuedCount > 0 ? 1 : 0)
    if (name === "history") return root.historyCount + (root.historyCount > 0 ? 1 : 0)
    return 0
  }

  function clampIndex() {
    var max = sectionCount(root.focusSection) - 1
    if (root.selectedIndex > max) root.selectedIndex = Math.max(0, max)
    if (root.selectedIndex < 0) root.selectedIndex = 0
  }

  function focusSectionAt(name, index) {
    if (root.settingsPanelVisible && name !== "settings") return
    root.focusSection = name
    root.selectedIndex = index
    root.cursorActive = true
    root.clampIndex()
    Qt.callLater(root.scrollToCursor)
  }

  function moveCursor(dx, dy) {
    if (!root.cursorActive) {
      root.cursorActive = true
      root.clampIndex()
      return
    }
    if (dy !== 0 || dx !== 0) {
      var direction = dy !== 0 ? dy : dx
      var count = sectionCount(root.focusSection)
      var ni = root.selectedIndex + direction
      if (ni >= count) {
        var s = root.sectionList()
        var i = s.indexOf(root.focusSection)
        root.focusSection = s[(i + 1) % s.length]
        root.selectedIndex = 0
        root.clampIndex()
      } else if (ni < 0) {
        var s2 = root.sectionList()
        var i2 = s2.indexOf(root.focusSection)
        root.focusSection = s2[(i2 - 1 + s2.length) % s2.length]
        root.selectedIndex = sectionCount(root.focusSection) - 1
        root.clampIndex()
      } else {
        root.selectedIndex = ni
      }
      Qt.callLater(root.scrollToCursor)
    }
  }

  function activateCursor() {
    if (!root.cursorActive) {
      root.cursorActive = true
      return
    }
    var s = root.focusSection
    if (s === "settings") {
      if (settingsPanelLoader.item) {
        settingsPanelLoader.item.activateIndex(root.selectedIndex)
      }
    } else if (s === "install") {
      if (ytdlService && !ytdlService.installing) ytdlService.installInTerminal()
    } else if (s === "input") {
      if (root.selectedIndex === 0) root.focusUrlField()
      else if (root.selectedIndex === 1) root.openSettings()
      else root.submitUrl()
    } else if (s === "detected") {
      if (ytdlService && ytdlService.detectedUrl) {
        ytdlService.startDownload(ytdlService.detectedUrl, ytdlService.selectedQuality, false, ytdlService.detectedTitle || "", ytdlService.defaultDownloadType)
        ytdlService.clearDetection()
      }
    } else if (s === "playlist") {
      if (ytdlService && ytdlService.playlistInfoUrl) {
        ytdlService.startPlaylist(ytdlService.playlistInfoUrl, ytdlService.selectedQuality, ytdlService.defaultDownloadType)
        ytdlService.clearPlaylistInfo()
      }
    } else if (s === "downloads") {
      if (root.selectedIndex === 0) {
        if (ytdlService) ytdlService.cancelAll()
      } else {
        var d = root.activeDownloads[root.selectedIndex - 1]
        if (d && ytdlService) ytdlService.cancelDownload(d.dwnId)
      }
    } else if (s === "queue") {
      if (root.selectedIndex === 0) {
        if (ytdlService) ytdlService.clearQueue()
      } else {
        var q = root.queuedDownloads[root.selectedIndex - 1]
        if (q && ytdlService) ytdlService.removeQueued(q.dwnId)
      }
    } else if (s === "history") {
      if (root.selectedIndex === 0) {
        if (root.hasRetryableItems && ytdlService) ytdlService.retryAll()
        else if (ytdlService) ytdlService.clearHistory()
      } else {
        var h = root.historyItems[root.selectedIndex - 1]
        if (h && ytdlService) {
          if (h.status === "done") ytdlService.playFile(h.filepath)
          else if (h.status === "error" || h.status === "cancelled") ytdlService.retryDownload(h)
        }
      }
    }
  }

  function deleteCursor() {
    if (!root.cursorActive) return
    if (root.focusSection === "settings") {
      root.closeSettings()
    } else if (root.focusSection === "detected") {
      if (ytdlService) ytdlService.clearDetection()
    } else if (root.focusSection === "playlist") {
      if (ytdlService) ytdlService.clearPlaylistInfo()
    } else if (root.focusSection === "downloads") {
      if (root.selectedIndex === 0) {
        if (ytdlService) ytdlService.cancelAll()
      } else {
        var d = root.activeDownloads[root.selectedIndex - 1]
        if (d && ytdlService) ytdlService.cancelDownload(d.dwnId)
      }
    } else if (root.focusSection === "queue") {
      if (root.selectedIndex === 0) {
        if (ytdlService) ytdlService.clearQueue()
      } else {
        var q = root.queuedDownloads[root.selectedIndex - 1]
        if (q && ytdlService) ytdlService.removeQueued(q.dwnId)
      }
    } else if (root.focusSection === "history") {
      if (root.selectedIndex === 0) {
        if (ytdlService) ytdlService.clearHistory()
      } else {
        var h = root.historyItems[root.selectedIndex - 1]
        if (h && ytdlService) ytdlService.removeHistoryItem(h.dwnId)
      }
    }
  }

  function handleTextKey(t) {
    if (root.settingsPanelVisible) {
      if (t === "q" || t === "Q" || t === "Escape") {
        root.closeSettings()
      }
    } else {
      if (t === "/") root.focusUrlField()
      else if (t === "s" || t === "S") root.openSettings()
    }
  }

  function scrollToCursor() {
    if (root.settingsPanelVisible) {
      if (settingsPanelLoader.item) {
        settingsPanelLoader.item.scrollToCursor()
      }
      return
    }
    if (!flick) return
    var item = null
    if (root.focusSection === "input") {
      if (root.selectedIndex === 0 && urlInput) item = urlInput
      else if (root.selectedIndex === 1 && settingsBtn) item = settingsBtn
      else if (root.selectedIndex === 2 && downloadManualBtn) item = downloadManualBtn
    } else if (root.focusSection === "detected")
      item = flick.contentItem.parent.detectedColumn
    else if (root.focusSection === "playlist")
      item = flick.contentItem.parent.playlistColumn
    else if (root.focusSection === "downloads" && root.selectedIndex > 0 && activeRepeater.count > 0)
      item = activeRepeater.itemAt(root.selectedIndex - 1)
    else if (root.focusSection === "queue" && root.selectedIndex > 0 && queueRepeater.count > 0)
      item = queueRepeater.itemAt(root.selectedIndex - 1)
    else if (root.focusSection === "history" && root.selectedIndex > 0 && historyRepeater.count > 0)
      item = historyRepeater.itemAt(root.selectedIndex - 1)
    if (!item) return
    var y = item.mapToItem(flick.contentItem, 0, 0).y
    if (y < flick.contentY) flick.contentY = Math.max(0, y - Style.space(8))
    else if (y + item.height > flick.contentY + flick.height)
      flick.contentY = y + item.height - flick.height + Style.space(8)
  }

  onActiveCountChanged: {
    if (root.activeCount === 0 && root.focusSection === "downloads" && root.cursorActive) {
      root.focusSection = "input"
      root.selectedIndex = 0
    } else if (root.focusSection === "downloads") {
      root.clampIndex()
    }
  }

  onDetectedSectionVisibleChanged: {
    if (!root.detectedSectionVisible && root.focusSection === "detected" && root.cursorActive) {
      root.focusSection = "input"
      root.selectedIndex = 0
    }
  }

  onPlaylistSectionVisibleChanged: {
    if (!root.playlistSectionVisible && root.focusSection === "playlist" && root.cursorActive) {
      root.focusSection = "input"
      root.selectedIndex = 0
    }
  }

  onQueuedCountChanged: {
    if (root.queuedCount === 0 && root.focusSection === "queue" && root.cursorActive) {
      root.focusSection = "input"
      root.selectedIndex = 0
    } else if (root.focusSection === "queue") {
      root.clampIndex()
    }
  }

  onHistoryCountChanged: {
    if (root.historyCount === 0 && root.focusSection === "history" && root.cursorActive) {
      root.focusSection = "input"
      root.selectedIndex = 0
    } else if (root.focusSection === "history") {
      root.clampIndex()
    }
  }

  Component.onCompleted: {
    root.wireService()
    if (ytdlService) ytdlService.checkInstallation()
  }

  onYtdlServiceChanged: Qt.callLater(root.wireService)

  // Debounces the playlist-info lookup while the user types or edits the URL.
  Timer {
    id: playlistInfoTimer
    interval: 450
    repeat: false
    onTriggered: {
      if (ytdlService) ytdlService.fetchPlaylistInfo(root.inputUrl)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    // SettingsPanel is a Flickable with no implicitHeight, so the card sizes
    // from its exposed preferredHeight when the settings page is showing.
    contentHeight: panel.fittedContentHeight(
      root.settingsPanelVisible && settingsPanelLoader.item
        ? settingsPanelLoader.item.preferredHeight
        : flick.contentHeight,
      root.settingsPanelVisible ? Style.space(560) : Style.space(500))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Let the URL field, a settings dropdown popup, or the languages input
      // own all keys while they are focused.
      blocked: urlInput.activeFocus
        || (settingsPanelLoader.active && settingsPanelLoader.item
            && (settingsPanelLoader.item.isPopupOpen || settingsPanelLoader.item.isInputActive))

      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: {
        if (root.settingsPanelVisible) root.closeSettings()
        else root.close()
      }
      onDeleteRequested: root.deleteCursor()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { root.handleTextKey(t) }

      // Main Download view
      Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        visible: !root.settingsPanelVisible

        Column {
          id: content
          width: parent.width
          spacing: Style.space(16)

          Column {
            visible: !root.installed && root.ytdlService && !root.ytdlService.checkingInstallation
            width: parent.width
            spacing: Style.space(14)

            Item {
              width: parent.width
              implicitHeight: Style.space(56)

              Text {
                anchors.centerIn: parent
                text: ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display + Style.space(8)
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                width: parent.width
                text: "yt-dlp is not installed."
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }

              Text {
                width: parent.width
                text: "Install yt-dlp to download videos from YouTube and other sites."
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
              }
            }

            Button {
              width: parent.width
              text: root.ytdlService && root.ytdlService.installing
                ? "Installing yt-dlp\u2026"
                : "Install yt-dlp"
              iconText: root.ytdlService && root.ytdlService.installing ? "" : ""
              iconSpinning: root.ytdlService && root.ytdlService.installing
              fontFamily: root.fontFamily
              fontSize: Style.font.body
              iconSize: Style.font.icon
              foreground: root.foreground
              accent: root.activeColor
              verticalPadding: Style.space(14)
              bordered: true
              selected: true
              hasCursor: root.cursorActive && root.focusSection === "install"
              enabled: !(root.ytdlService && root.ytdlService.installing)
              onHovered: function(hovered) {
                if (hovered) root.focusSectionAt("install", 0)
              }
              onClicked: {
                if (root.ytdlService) {
                  if (root.ytdlService.installing) return
                  root.ytdlService.installInTerminal()
                }
              }
            }
          }

          Column {
            visible: root.installed
            width: parent.width
            spacing: Style.space(4)

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: urlInput
                Layout.fillWidth: true
                height: Style.space(36)
                placeholderText: "Paste URL here\u2026"
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                foreground: root.foreground
                accent: root.activeColor
                hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === 0
                onAccepted: root.submitUrl()
                onHoveredChanged: if (hovered) root.focusSectionAt("input", 0)
                onTextChanged: {
                  root.inputUrl = text
                  if (text !== root.clipboardUrl) root.clipboardUrl = ""
                  playlistInfoTimer.restart()
                }
                Keys.onEscapePressed: root.focusPanel()
              }

              Button {
                id: settingsBtn
                text: root.selectionSummary
                tooltipText: "Download settings"
                fontSize: Style.font.caption
                foreground: root.foreground
                accent: root.activeColor
                bordered: true
                implicitHeight: Style.space(36)
                hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === 1
                onHovered: function(hovered) {
                  if (hovered) root.focusSectionAt("input", 1)
                }
                onClicked: root.openSettings()
              }

              Button {
                id: downloadManualBtn
                iconText: ""
                tooltipText: "Download"
                foreground: root.foreground
                accent: root.activeColor
                iconSize: Style.font.icon
                implicitWidth: Style.space(36)
                implicitHeight: Style.space(36)
                horizontalPadding: 0
                verticalPadding: 0
                enabled: root.inputUrl !== ""
                opacity: enabled ? 1 : 0.35
                hasCursor: root.cursorActive && root.focusSection === "input" && root.selectedIndex === 2
                onHovered: function(hovered) {
                  if (hovered) root.focusSectionAt("input", 2)
                }
                onClicked: root.submitUrl()
              }
            }

            Text {
              visible: root.clipboardUrl !== ""
              width: parent.width
              text: "URL detected from clipboard"
              color: root.activeColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // YouTube detected via MPRIS: browser is playing a YouTube video,
          // offer a one-click download without manually pasting the URL.
          Column {
            objectName: "detectedColumn"
            visible: root.detectedSectionVisible
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Column {
                Layout.fillWidth: true
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: "YouTube video from browser detected"
                  color: root.activeColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: ytdlService ? (ytdlService.detectedTitle || ytdlService.detectedUrl) : ""
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  maximumLineCount: 1
                }
              }

              Button {
                iconText: ""
                tooltipText: "Download this video"
                foreground: root.foreground
                accent: root.activeColor
                iconSize: Style.font.icon
                implicitWidth: Style.space(36)
                implicitHeight: Style.space(36)
                horizontalPadding: 0
                verticalPadding: 0
                hasCursor: root.cursorActive && root.focusSection === "detected"
                onClicked: {
                  if (ytdlService && ytdlService.detectedUrl) {
                    ytdlService.startDownload(ytdlService.detectedUrl, ytdlService.selectedQuality, false, ytdlService.detectedTitle || "", ytdlService.defaultDownloadType)
                    ytdlService.clearDetection()
                  }
                }
              }
            }
          }

          // Playlist detected: a video URL copied from a playlist page offers the
          // whole playlist as an explicit action instead of surprising downloads.
          Column {
            objectName: "playlistColumn"
            visible: root.playlistSectionVisible
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Column {
                Layout.fillWidth: true
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: "Playlist detected"
                  color: root.activeColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: ytdlService
                    ? (ytdlService.playlistInfoLoading ? "Resolving playlist\u2026"
                       : ytdlService.playlistInfoError ? "Could not resolve playlist"
                       : ytdlService.playlistInfoName
                         ? ytdlService.playlistInfoName + " \u00b7 " + ytdlService.playlistInfoCount
                           + (ytdlService.playlistInfoCount === 1 ? " video" : " videos")
                         : "")
                    : ""
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  maximumLineCount: 1
                }
              }

              Button {
                iconText: ""
                tooltipText: "Download the whole playlist"
                foreground: root.foreground
                accent: root.activeColor
                iconSize: Style.font.icon
                implicitWidth: Style.space(36)
                implicitHeight: Style.space(36)
                horizontalPadding: 0
                verticalPadding: 0
                hasCursor: root.cursorActive && root.focusSection === "playlist"
                onClicked: {
                  if (ytdlService && ytdlService.playlistInfoUrl) {
                    ytdlService.startPlaylist(ytdlService.playlistInfoUrl, ytdlService.selectedQuality, ytdlService.defaultDownloadType)
                    ytdlService.clearPlaylistInfo()
                    root.clipboardUrl = ""
                    root.inputUrl = ""
                    urlInput.text = ""
                  }
                }
              }
            }
          }

          Column {
            visible: root.installed && root.activeCount > 0
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                text: " Active Downloads (" + root.activeCount + ")"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
              }

              PanelActionButton {
                iconText: "󰅙"
                tooltipText: "Cancel all downloads"
                foreground: root.foreground
                hoverColor: Color.urgent
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                hasCursor: root.cursorActive && root.focusSection === "downloads" && root.selectedIndex === 0
                onClicked: {
                  if (ytdlService) ytdlService.cancelAll()
                }
              }
            }

            Repeater {
              id: activeRepeater
              model: root.activeDownloads

              delegate: CursorSurface {
                width: parent.width
                height: dlBody.implicitHeight + Style.space(16)
                foreground: root.foreground
                accent: root.activeColor
                hasCursor: root.cursorActive && root.focusSection === "downloads" && root.selectedIndex === index + 1
                  || root.hoverSection === "downloads" && root.hoverIndex === index

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onContainsMouseChanged: {
                    if (containsMouse) {
                      root.hoverSection = "downloads"
                      root.hoverIndex = index
                    } else if (root.hoverSection === "downloads" && root.hoverIndex === index) {
                      root.hoverSection = ""
                      root.hoverIndex = -1
                    }
                  }
                  onClicked: root.focusSectionAt("downloads", index)
                }

                Column {
                  id: dlBody
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(6)

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(6)

                    Text {
                      Layout.fillWidth: true
                      text: modelData.displayTitle || modelData.title || "Fetching title\u2026"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }

                    PanelActionButton {
                      id: cancelBtn
                      iconText: ""
                      tooltipText: "Cancel download"
                      foreground: root.foreground
                      hoverColor: Color.urgent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.bodySmall
                      onClicked: {
                        if (ytdlService) ytdlService.cancelDownload(modelData.dwnId)
                      }
                    }
                  }

                  Rectangle {
                    width: parent.width
                    height: Style.space(5)
                    radius: height / 2
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)

                    Rectangle {
                      width: Math.max(height, parent.width * (Math.max(0, Math.min(100, modelData.progress)) / 100))
                      height: parent.height
                      radius: parent.radius
                      color: root.activeColor

                      Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                  }

                  RowLayout {
                    width: parent.width
                    spacing: Style.space(8)

                    Text {
                      Layout.fillWidth: true
                      text: modelData.speed || "Waiting\u2026"
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }

                    Text {
                      text: modelData.eta ? "Time remaining " + modelData.eta : ""
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }

          // Queue section: downloads waiting for a free slot (max 3 parallel).
          Column {
            visible: root.installed && root.queuedCount > 0
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                text: "󰐑 Queue (" + root.queuedCount + ")"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
              }

              PanelActionButton {
                iconText: ""
                tooltipText: "Clear queue"
                foreground: root.foreground
                hoverColor: Color.urgent
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                hasCursor: root.cursorActive && root.focusSection === "queue" && root.selectedIndex === 0
                onClicked: {
                  if (ytdlService) ytdlService.clearQueue()
                }
              }
            }

            Repeater {
              id: queueRepeater
              model: root.queuedDownloads

              delegate: CursorSurface {
                width: parent.width
                height: qBody.implicitHeight + Style.space(12)
                foreground: root.foreground
                accent: root.activeColor
                hasCursor: root.cursorActive && root.focusSection === "queue" && root.selectedIndex === index + 1
                  || root.hoverSection === "queue" && root.hoverIndex === index

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onContainsMouseChanged: {
                    if (containsMouse) {
                      root.hoverSection = "queue"
                      root.hoverIndex = index
                    } else if (root.hoverSection === "queue" && root.hoverIndex === index) {
                      root.hoverSection = ""
                      root.hoverIndex = -1
                    }
                  }
                  onClicked: root.focusSectionAt("queue", index)
                }

                RowLayout {
                  id: qBody
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(6)

                  Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: modelData.displayTitle || modelData.title || "Unknown"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }

                    Text {
                      width: parent.width
                      text: "In queue"
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }
                  }

                  PanelActionButton {
                    iconText: ""
                    tooltipText: "Remove from queue"
                    foreground: root.foreground
                    hoverColor: Color.urgent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    onClicked: {
                      if (ytdlService) ytdlService.removeQueued(modelData.dwnId)
                    }
                  }
                }
              }
            }
          }

          Column {
            visible: root.installed && root.historyCount > 0
              && (!ytdlService || ytdlService.enableHistory)
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              width: parent.width
              height: 1
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Text {
                Layout.fillWidth: true
                text: " History (" + root.historyCount + ")"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
              }

              PanelActionButton {
                visible: root.hasRetryableItems
                iconText: ""
                tooltipText: "Retry all failed/cancelled"
                foreground: root.foreground
                hoverColor: root.activeColor
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                hasCursor: root.cursorActive && root.focusSection === "history" && root.selectedIndex === 0 && root.hasRetryableItems
                onClicked: {
                  if (ytdlService) ytdlService.retryAll()
                }
              }

              PanelActionButton {
                iconText: ""
                tooltipText: "Clear history"
                foreground: root.foreground
                hoverColor: Color.urgent
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                hasCursor: root.cursorActive && root.focusSection === "history" && root.selectedIndex === 0
                onClicked: {
                  if (ytdlService) ytdlService.clearHistory()
                }
              }
            }

            Repeater {
              id: historyRepeater
              model: root.historyItems

              delegate: CursorSurface {
                width: parent.width
                height: histBody.implicitHeight + Style.space(12)
                foreground: root.foreground
                accent: root.activeColor
                hasCursor: root.cursorActive && root.focusSection === "history" && root.selectedIndex === index + 1
                  || root.hoverSection === "history" && root.hoverIndex === index

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onContainsMouseChanged: {
                    if (containsMouse) {
                      root.hoverSection = "history"
                      root.hoverIndex = index
                    } else if (root.hoverSection === "history" && root.hoverIndex === index) {
                      root.hoverSection = ""
                      root.hoverIndex = -1
                    }
                  }

                  onClicked: {
                    root.focusSectionAt("history", index)
                    if (modelData.status === "done" && modelData._downloadType !== "transcript") {
                      if (ytdlService) ytdlService.playFile(modelData.filepath)
                    } else if (modelData.status === "error" || modelData.status === "cancelled") {
                      if (ytdlService) ytdlService.retryDownload(modelData)
                    }
                  }
                }

                RowLayout {
                  id: histBody
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(6)

                  Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: modelData.status === "done" ? ""
                      : modelData.status === "error" ? ""
                      : modelData.status === "cancelled" ? "󰜺"
                      : modelData.status === "unavailable" ? ""
                      : ""
                    color: modelData.status === "done" ? "#4ade80"
                      : modelData.status === "error" ? Color.urgent
                      : Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  Column {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Style.space(2)

                    Text {
                      width: parent.width
                      text: modelData.displayTitle || modelData.title || "Unknown"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }

                    Text {
                      width: parent.width
                      text: {
                        if (modelData.status === "done") return "Completed"
                        if (modelData.status === "unavailable") return "Subtitles not available"
                        if (modelData.status === "error") return modelData.error || "Download failed"
                        if (modelData.status === "cancelled") return "Cancelled"
                        return modelData.status
                      }
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }
                  }

                  Row {
                    id: actions
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Style.space(4)

                    PanelActionButton {
                      visible: modelData.status === "error" || modelData.status === "cancelled"
                      iconText: ""
                      tooltipText: "Retry"
                      foreground: root.foreground
                      hoverColor: root.activeColor
                      fontFamily: root.fontFamily
                      fontSize: Style.font.bodySmall
                      onClicked: {
                        if (ytdlService) ytdlService.retryDownload(modelData)
                      }
                    }

                    PanelActionButton {
                      visible: modelData.status === "done"
                      iconText: ""
                      tooltipText: "Delete file"
                      foreground: root.foreground
                      hoverColor: Color.urgent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.bodySmall
                      onClicked: {
                        if (ytdlService) ytdlService.deleteHistoryItem(modelData.dwnId)
                      }
                    }

                    PanelActionButton {
                      iconText: ""
                      tooltipText: "Remove from history"
                      foreground: root.foreground
                      hoverColor: Color.urgent
                      fontFamily: root.fontFamily
                      fontSize: Style.font.bodySmall
                      onClicked: {
                        if (ytdlService) ytdlService.removeHistoryItem(modelData.dwnId)
                      }
                    }
                  }
                }
              }
            }
          }

          Column {
            visible: root.installed && root.activeCount === 0 && root.historyCount === 0
            width: parent.width
            spacing: Style.space(10)

            Item {
              width: parent.width
              implicitHeight: Style.space(48)
              visible: !root.playlistSectionVisible && !root.detectedSectionVisible

              Text {
                anchors.centerIn: parent
                text: ""
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                opacity: 0.4
              }
            }

            Text {
              width: parent.width
              text: "Paste a YouTube URL or playlist above to start downloading."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }
        }
      }

      // Settings Panel loaded overlay
      Loader {
        id: settingsPanelLoader
        anchors.fill: parent
        active: root.settingsPanelVisible
        visible: root.settingsPanelVisible
        source: "SettingsPanel.qml"
        onLoaded: {
          item.ytdlService = root.ytdlService
          item.foreground = root.foreground
          item.activeColor = root.activeColor
          item.fontFamily = root.fontFamily
          item.cursorActive = Qt.binding(function() { return root.cursorActive && root.focusSection === "settings" })
          item.selectedIndex = Qt.binding(function() { return root.selectedIndex })
          item.closeRequested.connect(root.closeSettings)
          item.inputClosed.connect(root.focusPanel)
          item.cursorMoveRequested.connect(function(i) { root.focusSectionAt("settings", i) })
        }
      }
    }
  }
}
