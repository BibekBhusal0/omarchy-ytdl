import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// Labeled, scrollable settings view for the downloader.
// It is dynamically sized and keyboard-navigable.
Flickable {
  id: root
  clip: true
  contentWidth: width
  contentHeight: contentColumn.implicitHeight
  boundsBehavior: Flickable.StopAtBounds

  property var ytdlService: null
  property color foreground: Color.popups.text
  property color activeColor: Color.accent
  property string fontFamily: Style.font.family

  property bool cursorActive: false
  property int selectedIndex: 0

  signal closeRequested()
  signal inputClosed()
  signal cursorMoveRequested(int index)

  // The panel card sizes itself from this; Flickable reports no
  // implicitHeight of its own.
  readonly property real preferredHeight: contentColumn.implicitHeight

  onSelectedIndexChanged: Qt.callLater(root.scrollToCursor)
  onCursorActiveChanged: Qt.callLater(root.scrollToCursor)

  // Expose popupOpen so the parent key catcher knows to block keys while a dropdown is active.
  readonly property bool isPopupOpen: typeDropdown.popupOpen || qualityDropdown.popupOpen

  // While a text field owns focus, every keystroke must reach it
  // instead of the parent key catcher.
  readonly property bool isInputActive: langInput.activeFocus || downloadPathInput.activeFocus

  // Mouse hover on any control moves the shared cursor so keyboard and
  // pointer highlight stay in sync (the parent owns selectedIndex).
  function hoverKey(itemKey) {
    var i = visibleItems.indexOf(itemKey)
    if (i >= 0) cursorMoveRequested(i)
  }

  // Return the ordered list of visible settings controls for keyboard cursor indexing.
  readonly property var visibleItems: {
    var items = ["type"];
    if (ytdlService && ytdlService.defaultDownloadType !== "audio") {
      items.push("quality");
    }
    items.push("downloadPath");
    items.push("transcripts");
    if (ytdlService && ytdlService.downloadTranscripts) {
      items.push("languages");
    }
    items.push("playlistFolder");
    items.push("back");
    return items;
  }

  function getSelectedIndexForItem(itemKey) {
    return visibleItems.indexOf(itemKey);
  }

  function activateIndex(idx) {
    if (idx < 0 || idx >= visibleItems.length) return;
    var itemKey = visibleItems[idx];
    if (itemKey === "type") {
      typeDropdown.toggle();
    } else if (itemKey === "quality") {
      qualityDropdown.toggle();
    } else if (itemKey === "downloadPath") {
      downloadPathInput.forceActiveFocus();
    } else if (itemKey === "transcripts") {
      if (ytdlService) {
        ytdlService.updateSetting("downloadTranscripts", !ytdlService.downloadTranscripts);
      }
    } else if (itemKey === "languages") {
      langInput.forceActiveFocus();
    } else if (itemKey === "playlistFolder") {
      if (ytdlService) {
        ytdlService.updateSetting("playlistInSeparateFolder", !ytdlService.playlistInSeparateFolder);
      }
    } else if (itemKey === "back") {
      root.closeRequested();
    }
  }

  function scrollToCursor() {
    if (!root.cursorActive || selectedIndex < 0 || selectedIndex >= visibleItems.length) return;
    var itemKey = visibleItems[selectedIndex];
    var item = null;
    if (itemKey === "type") item = typeDropdown;
    else if (itemKey === "quality") item = qualityDropdown;
    else if (itemKey === "downloadPath") item = downloadPathInput;
    else if (itemKey === "transcripts") item = transcriptsToggle;
    else if (itemKey === "languages") item = langInput;
    else if (itemKey === "playlistFolder") item = playlistFolderToggle;
    else if (itemKey === "back") item = backBtn;

    if (!item) return;
    var y = item.mapToItem(contentColumn, 0, 0).y;
    if (y < root.contentY) {
      root.contentY = Math.max(0, y - Style.space(8));
    } else if (y + item.height > root.contentY + root.height) {
      root.contentY = y + item.height - root.height + Style.space(8);
    }
  }

  Column {
    id: contentColumn
    width: parent.width
    spacing: Style.space(14)

    Text {
      Layout.fillWidth: true
      text: "Downloader Settings"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
    }

    // Download Type dropdown
    Dropdown {
      id: typeDropdown
      width: parent.width
      label: "Download Type"
      value: ytdlService ? ytdlService.defaultDownloadType : "video"
      options: [
        { value: "video", label: "Video" },
        { value: "audio", label: "Audio" },
        { value: "both", label: "Video & Audio" }
      ]
      hasCursor: root.cursorActive && root.visibleItems[root.selectedIndex] === "type"
      onHovered: function(isHovered) {
        if (isHovered) root.hoverKey("type")
      }
      onChanged: function(val) {
        if (ytdlService) ytdlService.updateSetting("defaultDownloadType", val);
      }
    }

    // Video Quality dropdown
    Dropdown {
      id: qualityDropdown
      width: parent.width
      label: "Video Quality"
      value: ytdlService ? ytdlService.selectedQuality : "1080p"
      options: [
        { value: "best", label: "Best available" },
        { value: "1080p", label: "1080p" },
        { value: "720p", label: "720p" },
        { value: "480p", label: "480p" }
      ]
      visible: ytdlService && ytdlService.defaultDownloadType !== "audio"
      hasCursor: root.cursorActive && root.visibleItems[root.selectedIndex] === "quality"
      onHovered: function(isHovered) {
        if (isHovered) root.hoverKey("quality")
      }
      onChanged: function(val) {
        if (ytdlService) ytdlService.updateSetting("selectedQuality", val);
      }
    }

    // Download Path text input
    Column {
      width: parent.width
      spacing: Style.spacing.labelGap

      Text {
        text: "Download Path"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      TextField {
        id: downloadPathInput
        width: parent.width
        height: Style.spacing.controlHeight
        text: ytdlService ? ytdlService.downloadLocation : "~/Downloads/yt-dlp"
        placeholderText: "~/Downloads/yt-dlp"
        hasCursor: root.cursorActive && root.visibleItems[root.selectedIndex] === "downloadPath"
        onHoveredChanged: if (hovered) root.hoverKey("downloadPath")
        onAccepted: {
          if (ytdlService && text.trim()) ytdlService.updateSetting("downloadLocation", text.trim());
          downloadPathInput.focus = false;
          root.inputClosed();
        }
        Keys.onEscapePressed: {
          downloadPathInput.focus = false;
          root.inputClosed();
        }
      }
    }

    // Download Transcripts toggle row
    Toggle {
      id: transcriptsToggle
      width: parent.width
      label: "Download Transcripts"
      description: "Download subtitles/transcripts automatically."
      checked: ytdlService ? ytdlService.downloadTranscripts : false
      hasCursor: root.cursorActive && root.visibleItems[root.selectedIndex] === "transcripts"
      onHovered: function(isHovered) {
        if (isHovered) root.hoverKey("transcripts")
      }
      onClicked: {
        if (ytdlService) {
          ytdlService.updateSetting("downloadTranscripts", !ytdlService.downloadTranscripts);
        }
      }
    }

    // Transcript languages text input
    Column {
      width: parent.width
      spacing: Style.spacing.labelGap
      visible: ytdlService && ytdlService.downloadTranscripts

      Text {
        text: "Transcript Languages"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      TextField {
        id: langInput
        width: parent.width
        height: Style.spacing.controlHeight
        text: ytdlService ? ytdlService.transcriptLanguages : "en"
        placeholderText: "Comma-separated codes (e.g., en,es,fr) or 'all'"
        hasCursor: root.cursorActive && root.visibleItems[root.selectedIndex] === "languages"
        onHoveredChanged: if (hovered) root.hoverKey("languages")
        onAccepted: {
          if (ytdlService) ytdlService.updateSetting("transcriptLanguages", text);
          langInput.focus = false;
          root.inputClosed();
        }
        Keys.onEscapePressed: {
          langInput.focus = false;
          root.inputClosed();
        }
      }
    }

    // Playlists in separate folder toggle row
    Toggle {
      id: playlistFolderToggle
      width: parent.width
      label: "Playlist Subfolders"
      description: "Organize playlist items into a folder named after the playlist."
      checked: ytdlService ? ytdlService.playlistInSeparateFolder : true
      hasCursor: root.cursorActive && root.visibleItems[root.selectedIndex] === "playlistFolder"
      onHovered: function(isHovered) {
        if (isHovered) root.hoverKey("playlistFolder")
      }
      onClicked: {
        if (ytdlService) {
          ytdlService.updateSetting("playlistInSeparateFolder", !ytdlService.playlistInSeparateFolder);
        }
      }
    }

    // Back button at the bottom
    Button {
      id: backBtn
      width: parent.width
      height: Style.spacing.controlHeight
      text: "Back to downloads"
      iconText: ""
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      foreground: root.foreground
      accent: root.activeColor
      bordered: true
      hasCursor: root.cursorActive && root.visibleItems[root.selectedIndex] === "back"
      onHovered: function(isHovered) {
        if (isHovered) root.hoverKey("back")
      }
      onClicked: root.closeRequested()
    }
  }
}
