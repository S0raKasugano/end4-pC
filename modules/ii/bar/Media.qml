pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import qs.modules.common.models
import qs
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Item {
    id: root
    
    property bool vertical: false
    property bool borderless: Config.options.bar.borderless
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    readonly property MprisPlayer activePlayer: {
        const preferred = Config.options.bar.media.preferredPlayer.trim().toLowerCase()
        if (preferred.length === 0) return MprisController.activePlayer
        const _ = MprisController.players.count
        for (const p of MprisController.players) {
            if ((p.identity ?? "").toLowerCase().includes(preferred) ||
                (p.desktopEntry ?? "").toLowerCase().includes(preferred))
                return p
        }
        return MprisController.activePlayer
    }

    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    property var    artUrl:      activePlayer?.trackArtUrl ?? ""
    property string trackTitle:  activePlayer?.trackTitle  ?? ""
    property string trackArtist: activePlayer?.trackArtist ?? ""
    property bool   isPlaying:   activePlayer?.isPlaying   ?? false
    property bool   hasTrack:    trackTitle.length > 0

    property string artDownloadLocation: Directories.coverArt
    property string artFileName:         Qt.md5(artUrl)
    property string artFilePath:         `${artDownloadLocation}/${artFileName}`
    property bool   artDownloaded:       false

    property string displayedArtFilePath: {
        if (!root.artDownloaded) return ""
        if (root.artUrl.startsWith("file://")) return root.artUrl
        return Qt.resolvedUrl(artFilePath)
    }

    onArtFilePathChanged: {
        if (!root.artUrl || root.artUrl.length === 0) {
            root.artDownloaded = false
            return
        }
        if (root.artUrl.startsWith("file://")) {
            root.artDownloaded = true
            return
        }
        artDownloader.targetFile  = root.artUrl
        artDownloader.artFilePath = root.artFilePath
        root.artDownloaded = false
        artDownloader.running = true
    }

    Process {
        id: artDownloader
        property string targetFile:  root.artUrl
        property string artFilePath: root.artFilePath
        command: ["bash", "-c",
            `[ -f ${artFilePath} ] || curl -sSL '${targetFile}' -o '${artFilePath}'`]
        onExited: { root.artDownloaded = true }
    }

    Layout.fillHeight: true
    implicitWidth: vertical 
        ? Appearance.sizes.verticalBarWidth 
        : (isMaterial 
            ? materialRow.implicitWidth 
            : Math.max(
                Config.options.bar.media.minWidth,
                Math.min(rowLayout.implicitWidth + 8, Config.options.bar.media.maxWidth)
            ))
    implicitHeight: vertical ? (isMaterial ? 32 : mediaCircProg.implicitHeight) : Appearance.sizes.barHeight

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        hoverEnabled: !Config.options.bar.tooltips.clickToShow
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton)      activePlayer?.togglePlaying()
            else if (event.button === Qt.BackButton)   activePlayer?.previous()
            else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) activePlayer?.next()
            else if (event.button === Qt.LeftButton)   GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
        }
    }

    // Vertical default
    Loader {
        id: mediaCircProg
        active: root.vertical && !root.isMaterial
        visible: active
        anchors.centerIn: parent
        sourceComponent: ClippedFilledCircularProgress {
            implicitSize: 20
            lineWidth: Appearance.rounding.unsharpen
            value: root.activePlayer?.position / root.activePlayer?.length
            colPrimary: Appearance.colors.colOnSecondaryContainer
            enableAnimation: false
            Item {
                anchors.centerIn: parent
                width: 20
                height: 20
                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: root.activePlayer?.isPlaying ? "pause" : "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }
    }

    // Vertical Material
    Rectangle {
        visible: root.vertical && root.isMaterial
        anchors.centerIn: parent
        color: Appearance.colors.colSecondaryContainer
        radius: Appearance.rounding.full
        implicitWidth: 32
        implicitHeight: 32
        
        MaterialSymbol {
            anchors.centerIn: parent
            fill: 1
            text: root.activePlayer?.isPlaying ? "pause" : "music_note"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    // Horizontal default
    Loader {
        id: rowLayout
        active: !root.vertical && !root.isMaterial
        visible: active
        anchors.fill: parent
        sourceComponent: RowLayout {
            spacing: 4
            ClippedFilledCircularProgress {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 3
                implicitSize: 20
                lineWidth: Appearance.rounding.unsharpen
                value: root.activePlayer?.position / root.activePlayer?.length
                colPrimary: Appearance.colors.colOnSecondaryContainer
                enableAnimation: false
                Item {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    MaterialSymbol {
                        anchors.centerIn: parent
                        fill: 1
                        text: root.activePlayer?.isPlaying ? "pause" : "music_note"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.m3colors.m3onSecondaryContainer
                    }
                }
            }
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: LyricsService.status === "ok" ? defaultActiveLyricRow.implicitWidth + 16 : 250
                Layout.fillHeight: true
                clip: true

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8
                    visible: Config.options.bar.verbose && LyricsService.status !== "ok"
                    horizontalAlignment: Text.AlignLeft
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer1
                    text: Config.options.bar.media.onlyTitle ? root.cleanedTitle : `${root.cleanedTitle}${root.activePlayer?.trackArtist ? ' • ' + root.activePlayer.trackArtist : ''}`
                }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8
                    visible: Config.options.bar.verbose && LyricsService.status === "ok"
                    height: defaultLyricHeightRef.implicitHeight
                    
                    StyledText {
                        id: defaultLyricHeightRef
                        text: "T"
                        opacity: 0
                    }
                    
                    Item {
                        id: defaultLyricContainer
                        anchors.fill: parent
                        
                        property string text: LyricsService.slots[3] || "♪"
                        property var currentWords: LyricsService.activeIndex >= 0 && LyricsService.lyricsLines[LyricsService.activeIndex]?.words?.length > 0 ? LyricsService.lyricsLines[LyricsService.activeIndex].words : [{text: defaultLyricContainer.text, startTime: 0, duration: 0}]
                        property real elapsedTime: 0
                        
                        property int _activeIndex: LyricsService.activeIndex
                        
                        on_ActiveIndexChanged: {
                            elapsedTime = 0
                            if (LyricsService.activeLineDuration > 0) {
                                elapsedAnim.to = LyricsService.activeLineDuration
                                elapsedAnim.duration = LyricsService.activeLineDuration
                                elapsedAnim.restart()
                            }
                        }
                        
                        NumberAnimation {
                            id: elapsedAnim
                            target: defaultLyricContainer
                            property: "elapsedTime"
                            from: 0
                            easing.type: Easing.Linear
                        }
                        
                        Row {
                            id: defaultActiveLyricRow
                            anchors.fill: parent
                            spacing: 0
                            transform: Translate { id: defaultLyricTrans; y: 0 }
                            
                            Repeater {
                                model: defaultLyricContainer.currentWords.length
                                delegate: Item {
                                    required property int index
                                    property var wordData: defaultLyricContainer.currentWords[index]
                                    property bool isMusicNote: wordData && wordData.text === "♪"
                                    
                                    width: isMusicNote ? (tinyVisualizerLoader.item ? tinyVisualizerLoader.item.implicitWidth : 20) : wordBg.implicitWidth
                                    height: wordBg.implicitHeight
                                    
                                    Loader {
                                        id: tinyVisualizerLoader
                                        active: parent.isMusicNote
                                        anchors.verticalCenter: parent.verticalCenter
                                        sourceComponent: Visualizer {
                                            barCount: 4
                                            dotSize: 3
                                            dotSpacing: 2
                                            maxBarHeight: 12
                                            maxVisualizerValue: 300
                                            vertical: false
                                            implicitHeight: 12
                                            implicitWidth: (4 * (3 + 2))
                                            opacity: wordBg.opacity
                                        }
                                    }
                                    
                                    Text {
                                        id: wordBg
                                        visible: !parent.isMusicNote
                                        text: wordData && wordData.text !== undefined ? wordData.text : " "
                                        color: Appearance.colors.colPrimary
                                        opacity: {
                                            if (!wordData) return 0.3;
                                            const sTime = wordData.startTime !== undefined ? wordData.startTime : 0;
                                            return defaultLyricContainer.elapsedTime >= sTime ? 1.0 : 0.3;
                                        }
                                        font.family: Appearance.font.family.main
                                        font.pixelSize: Appearance.font.pixelSize.small ?? 15
                                        
                                        Behavior on opacity {
                                            NumberAnimation { duration: 100; easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Horizontal Material
    Loader {
        id: materialRow
        active: !root.vertical && root.isMaterial
        visible: active
        anchors.centerIn: parent
        sourceComponent: RowLayout {
            id: innerRow
            anchors.centerIn: parent
            spacing: 6

            // No platyer 
            Loader {
                active: !root.hasTrack
                visible: active
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: RowLayout {
                    spacing: 6

                    // Avatar
                    Rectangle {
                        id: avatarRect
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        Layout.alignment: Qt.AlignVCenter

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: avatarRect.width
                                height: avatarRect.height
                                radius: avatarRect.radius
                            }
                        }

                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            source: Config.options.profile.avatarPath !== "" 
                                ? "file://" + Config.options.profile.avatarPicture 
                                : "file:///home/" + (Quickshell.env("USER") ?? "user") + "/.face"
                            sourceSize.width: avatarRect.width * 2
                            sourceSize.height: avatarRect.height * 2
                            fillMode: Image.PreserveAspectCrop
                            onStatusChanged: {
                                if (status === Image.Error)
                                    visible = false
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "account_circle"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnPrimaryContainer
                            visible: avatarImage.status === Image.Error || avatarImage.status === Image.Null
                        }
                    }

                    ColumnLayout {
                        spacing: -3
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: 2

                        StyledText {
                            text: Config.options.profile.displayName === "" ? SystemInfo.username : Config.options.profile.displayName
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSecondaryContainer
                            elide: Text.ElideRight
                            Layout.maximumWidth: 120
                        }

                        StyledText {
                            id: distroLabel
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSecondaryContainer
                            opacity: 0.7
                            elide: Text.ElideRight
                            Layout.rightMargin: 8
                            Layout.maximumWidth: 120
                            text: SystemInfo.distroName
                        }
                    }
                }
            }

            // Player
            Loader {
                active: root.hasTrack
                visible: active
                Layout.alignment: Qt.AlignVCenter
                sourceComponent: RowLayout {
                    spacing: 6

                    // Art
                    Rectangle {
                        id: artRect
                        implicitWidth: 26
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer
                        Layout.alignment: Qt.AlignVCenter

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: artRect.width
                                height: artRect.height
                                radius: artRect.radius
                            }
                        }

                        StyledImage {
                            anchors.fill: parent
                            source: root.displayedArtFilePath
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            antialiasing: true
                            sourceSize.width: artRect.width
                            sourceSize.height: artRect.height
                            visible: root.displayedArtFilePath !== ""
                            
                            RotationAnimator on rotation {
                                loops: Animation.Infinite
                                from: 0; to: 360
                                duration: 8000
                                running: root.isPlaying
                            }
                        }

                        MaterialSymbol {
                            anchors.centerIn: parent
                            fill: 1
                            text: "music_note"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSecondaryContainer
                            visible: root.displayedArtFilePath === ""
                        }
                    }

                    // Title + Artist + Lyrics
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: LyricsService.status === "ok" ? activeLyricRow.implicitWidth + 12 : 250
                        implicitHeight: 32
                        clip: true
                        
                        ColumnLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            visible: LyricsService.status !== "ok"
                            spacing: -4

                            StyledText {
                                id: artistText
                                text: root.trackArtist
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                Behavior on text {
                                    SequentialAnimation {
                                        NumberAnimation { target: artistText; property: "x"; to: -artistText.width; duration: 150; easing.type: Easing.InQuad }
                                        PropertyAction { target: artistText; property: "text" }
                                        NumberAnimation { target: artistText; property: "x"; from: artistText.width; to: 0; duration: 150; easing.type: Easing.OutQuad }
                                    }
                                }
                            }
                            StyledText {
                                id: titleText
                                Layout.topMargin: (!root.activePlayer || root.trackArtist.length === 0) ? -13 : 0
                                text: StringUtils.cleanMusicTitle(root.trackTitle) || Translation.tr("No media")
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colOnSecondaryContainer
                                elide: Text.ElideRight
                                opacity: 0.7
                                Layout.fillWidth: true
                                Behavior on text {
                                    SequentialAnimation {
                                        NumberAnimation { target: titleText; property: "x"; to: -titleText.width; duration: 150; easing.type: Easing.InQuad }
                                        PropertyAction { target: titleText; property: "text" }
                                        NumberAnimation { target: titleText; property: "x"; from: titleText.width; to: 0; duration: 150; easing.type: Easing.OutQuad }
                                    }
                                }
                            }
                        }

                        Item {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            visible: LyricsService.status === "ok"
                            height: lyricHeightRef.implicitHeight
                            
                            StyledText {
                                id: lyricHeightRef
                                text: "T"
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                opacity: 0
                            }
                            
                            Item {
                                id: lyricContainer
                                anchors.fill: parent
                                
                                property string text: LyricsService.slots[3] || "♪"
                                property var currentWords: LyricsService.activeIndex >= 0 && LyricsService.lyricsLines[LyricsService.activeIndex]?.words?.length > 0 ? LyricsService.lyricsLines[LyricsService.activeIndex].words : [{text: lyricContainer.text, startTime: 0, duration: 0}]
                                property real elapsedTime: 0
                                
                                property int _activeIndex: LyricsService.activeIndex
                                
                                on_ActiveIndexChanged: {
                                    elapsedTime = 0
                                    if (LyricsService.activeLineDuration > 0) {
                                        hoverElapsedAnim.to = LyricsService.activeLineDuration
                                        hoverElapsedAnim.duration = LyricsService.activeLineDuration
                                        hoverElapsedAnim.restart()
                                    }
                                }
                                
                                NumberAnimation {
                                    id: hoverElapsedAnim
                                    target: lyricContainer
                                    property: "elapsedTime"
                                    from: 0
                                    easing.type: Easing.Linear
                                }
                                
                                Row {
                                    id: activeLyricRow
                                    anchors.fill: parent
                                    spacing: 0
                                    transform: Translate { id: lyricTrans; y: 0 }
                                    
                                    Repeater {
                                        model: lyricContainer.currentWords.length
                                        delegate: Item {
                                            required property int index
                                            property var wordData: lyricContainer.currentWords[index]
                                            property bool isMusicNote: wordData && wordData.text === "♪"
                                            
                                            width: isMusicNote ? (tinyVisualizerLoader.item ? tinyVisualizerLoader.item.implicitWidth : 20) : wordBg.implicitWidth
                                            height: wordBg.implicitHeight
                                            
                                            Loader {
                                                id: tinyVisualizerLoader
                                                active: parent.isMusicNote
                                                anchors.verticalCenter: parent.verticalCenter
                                                sourceComponent: Visualizer {
                                                    barCount: 4
                                                    dotSize: 3
                                                    dotSpacing: 2
                                                    maxBarHeight: 12
                                                    maxVisualizerValue: 300
                                                    vertical: false
                                                    implicitHeight: 12
                                                    implicitWidth: (4 * (3 + 2))
                                                    opacity: wordBg.opacity
                                                }
                                            }
                                            
                                            Text {
                                                id: wordBg
                                                visible: !parent.isMusicNote
                                                text: wordData && wordData.text !== undefined ? wordData.text : " "
                                                color: Appearance.colors.colPrimary
                                                opacity: {
                                                    if (!wordData) return 0.3;
                                                    const sTime = wordData.startTime !== undefined ? wordData.startTime : 0;
                                                    return lyricContainer.elapsedTime >= sTime ? 1.0 : 0.3;
                                                }
                                                font.family: Appearance.font.family.main
                                                font.pixelSize: Appearance.font.pixelSize.smallie
                                                
                                                Behavior on opacity {
                                                    NumberAnimation { duration: 100; easing.type: Easing.InOutQuad }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Play/Pause
                    RippleButton {
                        implicitWidth: 40
                        implicitHeight: 23
                        buttonRadius: root.isPlaying ? Appearance.rounding.normal : 13
                        colBackground: root.isPlaying ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerLow
                        colBackgroundHover: root.isPlaying ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimaryContainerHover
                        colRipple: root.isPlaying ? Appearance.colors.colPrimaryActive : Appearance.colors.colPrimaryContainerActive
                        downAction: () => root.activePlayer?.togglePlaying()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: root.isPlaying ? "pause" : "play_arrow"
                            iconSize: Appearance.font.pixelSize.large
                            fill: 1
                            color: root.isPlaying ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    // Next
                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 26
                        Layout.leftMargin: -4
                        buttonRadius: 13
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                        colRipple: Appearance.colors.colPrimaryContainerActive
                        downAction: () => root.activePlayer?.next()
                        altAction: () => root.activePlayer?.previous()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "skip_next"
                            iconSize: Appearance.font.pixelSize.large
                            fill: 1
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }
}
