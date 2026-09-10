import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"

Item {
    id: aboutTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    // ── BITE-OS modification ───────────────────────────────────────────
    // The panel used to key off Updater (serpantinum's own version), which on
    // BITE-OS can never be acted on. It now reports BITE-OS, read from the
    // same update.json that update_notifier.sh raises its notification from,
    // so the guide and the notification can never disagree. The panel stays
    // open either way, so the BITE-OS Update button is always reachable.
    property string biteLocal: ""
    property string biteRemote: ""
    property bool   biteUpdate: false
    property bool   biteChecked: false

    Process {
        id: biteUpdateProc
        running: false
        command: ["bash", "-c",
            "cat \"${XDG_STATE_HOME:-$HOME/.local/state}/bite-os/update.json\" 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let u = JSON.parse(this.text || "{}");
                    aboutTabRoot.biteLocal   = u.local  || "";
                    aboutTabRoot.biteRemote  = u.remote || "";
                    aboutTabRoot.biteUpdate  = u.available === true;
                    aboutTabRoot.biteChecked = (u.checked || 0) > 0;
                } catch (e) { aboutTabRoot.biteChecked = false; }
            }
        }
    }

    property real updateTransitionProgress: 1.0
    Behavior on updateTransitionProgress {
        NumberAnimation {
            duration: 450
            easing.type: Easing.OutQuint
        }
    }

    function activateTab() {
        if (typeof SystemInfo !== "undefined") {
            SystemInfo.fetch();
        }
    }

    onVisibleChanged: {
        if (visible) { activateTab(); biteUpdateProc.running = true; }
    }

    Component.onCompleted: {
        biteUpdateProc.running = true;
        if (visible) activateTab();
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainCol.implicitHeight + rootObj.s(32)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: rootObj.s(24)
            anchors.rightMargin: rootObj.s(24)
            anchors.topMargin: rootObj.s(16)
            spacing: rootObj.s(24)

            Item {
                id: headerArea
                Layout.fillWidth: true
                Layout.topMargin: rootObj.s(12)
                Layout.bottomMargin: rootObj.s(8)
                implicitHeight: Math.max(brandingContainer.implicitHeight, updatePanel.implicitHeight)

                readonly property real brandingW: rootObj.s(220)
                readonly property real panelW: rootObj.s(275)
                readonly property real gapW: rootObj.s(28)

                readonly property real collapsedX: (width - brandingW) / 2
                readonly property real expandedX: (width - (brandingW + gapW + panelW)) / 2

                Item {
                    id: brandingContainer
                    width: headerArea.brandingW
                    implicitHeight: brandingCol.implicitHeight
                    anchors.verticalCenter: parent.verticalCenter
                    x: headerArea.collapsedX + (headerArea.expandedX - headerArea.collapsedX) * aboutTabRoot.updateTransitionProgress

                    ColumnLayout {
                        id: brandingCol
                        anchors.centerIn: parent
                        spacing: rootObj.s(10)

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            width: rootObj.s(160)
                            height: width

                            Item {
                                id: aboutLogoMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true

                                Image {
                                    anchors.fill: parent
                                    source: "file://" + rootObj.appPaths.serpantinumDir + "/assets/logo.svg"
                                    sourceSize: Qt.size(512, 512)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    antialiasing: true
                                }
                            }

                            Item {
                                id: aboutLogoColor
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                layer.smooth: true

                                Rectangle {
                                    anchors.fill: parent
                                    color: ThemeBackend.mauve
                                }
                            }

                            MultiEffect {
                                anchors.fill: parent
                                source: aboutLogoColor
                                maskEnabled: true
                                maskSource: aboutLogoMask
                                autoPaddingEnabled: false
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(4)

                            Text {
                                text: I18n.t("guide.about.title")
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: rootObj.s(22)
                                color: ThemeBackend.text
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: I18n.t("guide.about.version_by", {
                                    version: (Updater.localVersion !== "..." ? Updater.localVersion : (rootObj.dotsVersion !== "Loading..." && rootObj.dotsVersion !== I18n.t("guide.about.loading") ? rootObj.dotsVersion : "2.0.0")),
                                    author: "@ilyamiro"
                                })
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(13)
                                color: ThemeBackend.subtext0
                                Layout.alignment: Qt.AlignHCenter
                            }

                            // ── BITE-OS modification ───────────────────────
                            // Added by GLITCH-BITE-404. Upstream's authorship
                            // line above is left untouched, as AGPL-3.0
                            // requires; this only notes the integration.
                            Text {
                                text: "BITE-OS rice \u00b7 GLITCH-BITE-404"
                                font.family: ThemeBackend.fontFamily
                                font.weight: Font.Bold
                                font.pixelSize: rootObj.s(12)
                                color: ThemeBackend.green
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Text {
                                text: "github.com/GLITCH-BITE-404/BITE-OS"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(11)
                                color: ThemeBackend.subtext0
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }
                }

                Item {
                    id: updatePanel
                    width: headerArea.panelW
                    anchors.verticalCenter: parent.verticalCenter
                    x: brandingContainer.x + brandingContainer.width + headerArea.gapW
                    implicitHeight: updateCol.implicitHeight
                    visible: opacity > 0.001
                    opacity: aboutTabRoot.updateTransitionProgress
                    transform: Translate { x: rootObj.s(16) * (1.0 - aboutTabRoot.updateTransitionProgress) }

                    ColumnLayout {
                        id: updateCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: rootObj.s(12)

                        Text {
                            Layout.alignment: Qt.AlignLeft
                            Layout.bottomMargin: rootObj.s(4)
                            text: aboutTabRoot.biteUpdate
                                  ? ("Update available  " + aboutTabRoot.biteRemote)
                                  : (aboutTabRoot.biteChecked ? "BITE-OS is up to date"
                                                              : "checking for updates…")
                            font.family: ThemeBackend.fontFamily
                            font.weight: Font.Bold
                            font.pixelSize: rootObj.s(18)
                            color: ThemeBackend.mauve
                        }

                        ClickButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: rootObj.s(36)
                            horizontalPadding: rootObj.s(14)
                            cornerRadius: ThemeBackend.borderRadius
                            buttonText: "Changelog"
                            textFontSize: rootObj.s(12)
                            buttonIcon: "󰈙"
                            iconFontSize: rootObj.s(16)
                            accentColor: ThemeBackend.surface0
                            textColor: ThemeBackend.text

                            onTriggered: Quickshell.execDetached(["xdg-open", "https://github.com/ilyamiro/serpantinum/blob/master/CHANGELOG.md"])
                        }

                        FillButton {
                            Layout.fillWidth: true
                            Layout.preferredHeight: rootObj.s(38)
                            buttonText: "BITE-OS Update"
                            buttonIcon: "󰚰"
                            accentColor: ThemeBackend.green
                            baseColor: ThemeBackend.surface0
                            hoverColor: Qt.alpha(ThemeBackend.green, 0.15)
                            textColor: ThemeBackend.green
                            filledTextColor: ThemeBackend.crust
                            cornerRadius: ThemeBackend.borderRadius
                            textFontSize: rootObj.s(12)
                            iconFontSize: rootObj.s(16)
                            fillDuration: 1200

                            // ── BITE-OS modification ───────────────────────
                            // Upstream ran `curl | bash` of install.sh here.
                            // On BITE-OS that is destructive: install.sh's
                            // migrate_legacy() REMOVES quickshell-git (which
                            // caelestia also needs), wipes the SDDM theme, and
                            // re-deploys upstream src/ over this rice's edits.
                            // Routed to the BITE-OS updater instead — the same
                            // thing Super+U runs.
                            onTriggered: {
                                Quickshell.execDetached(["bash", "-c",
                                    "kitty -e bite-os-update || ${TERMINAL:-xterm} -e bite-os-update"]);
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: rootObj.s(16)

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: rootObj.s(6)

                    Repeater {
                        id: hwRepeater
                        model: [
                            { icon: "󰌢", label: I18n.t("guide.about.hardware.device_name"), value: (typeof SystemInfo !== "undefined" && SystemInfo.hostname !== "") ? SystemInfo.hostname : I18n.t("guide.about.unknown") },
                            { icon: "󰻠", label: I18n.t("guide.about.hardware.processor"), value: (typeof SystemInfo !== "undefined" && SystemInfo.cpuModel !== "") ? SystemInfo.cpuModel + (SystemInfo.cpuCores > 0 ? " (" + SystemInfo.cpuCores + ")" : "") : I18n.t("guide.about.unknown") },
                            { icon: "󰢮", label: I18n.t("guide.about.hardware.graphics"), value: (typeof SystemInfo !== "undefined" && SystemInfo.gpuModel !== "") ? SystemInfo.gpuModel : I18n.t("guide.about.unknown") },
                            { icon: "󰍛", label: I18n.t("guide.about.hardware.memory"), value: (typeof SystemInfo !== "undefined" && SystemInfo.totalRamGb > 0) ? SystemInfo.totalRamGb + " GB" : I18n.t("guide.about.unknown") },
                            { icon: "󰋊", label: I18n.t("guide.about.hardware.disk_capacity"), value: (typeof SystemInfo !== "undefined" && SystemInfo.diskTotalGb > 0) ? SystemInfo.diskUsedGb + " / " + SystemInfo.diskTotalGb + " GB" : I18n.t("guide.about.unknown") }
                        ]

                        Rectangle {
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitHeight: rowHwLayout.implicitHeight + rootObj.s(20)
                            radius: ThemeBackend.borderRadius
                            color: Qt.alpha(ThemeBackend.surface0, 0.4)
                            border.width: 0

                            RowLayout {
                                id: rowHwLayout
                                anchors.left: parent.left
                                anchors.leftMargin: rootObj.s(14)
                                anchors.right: parent.right
                                anchors.rightMargin: rootObj.s(14)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: rootObj.s(12)

                                IconButton {
                                    enabled: false
                                    size: rootObj.s(32)
                                    Layout.preferredWidth: rootObj.s(32)
                                    Layout.preferredHeight: rootObj.s(32)
                                    Layout.alignment: Qt.AlignVCenter
                                    cornerRadius: ThemeBackend.borderRadius
                                    buttonIcon: modelData.icon
                                    iconFontSize: rootObj.s(16)
                                    accentColor: ThemeBackend.surface0
                                    textColor: "#ffffff"
                                }

                                Text {
                                    text: modelData.label
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(12)
                                    color: ThemeBackend.text
                                    Layout.preferredWidth: rootObj.s(105)
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: modelData.value
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(12)
                                    color: ThemeBackend.subtext0
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: rootObj.s(6)

                    Repeater {
                        id: sysRepeater
                        model: [
                            { icon: "⛁", label: I18n.t("guide.about.system.os_name"), value: (typeof SystemInfo !== "undefined" && SystemInfo.osName !== "") ? SystemInfo.osName : I18n.t("guide.about.system.default_os") },
                            { icon: "󰌽", label: I18n.t("guide.about.system.kernel_version"), value: (typeof SystemInfo !== "undefined" && SystemInfo.kernelVersion !== "") ? SystemInfo.kernelVersion : I18n.t("guide.about.unknown") },
                            { icon: "󰧨", label: I18n.t("guide.about.system.desktop"), value: (typeof SystemInfo !== "undefined" && SystemInfo.desktopEnv !== "") ? SystemInfo.desktopEnv : I18n.t("guide.about.unknown") },
                            { icon: "󰆍", label: I18n.t("guide.about.system.shell"), value: (typeof SystemInfo !== "undefined" && SystemInfo.shell !== "") ? SystemInfo.shell : I18n.t("guide.about.unknown") },
                            { icon: "󰔛", label: I18n.t("guide.about.system.uptime"), value: (typeof SystemInfo !== "undefined" && SystemInfo.uptime !== "") ? SystemInfo.uptime : I18n.t("guide.about.unknown") },
                            // BITE-OS: the distro's own version, next to the system facts
                            { icon: "", label: "BITE-OS", value: aboutTabRoot.biteLocal !== "" ? aboutTabRoot.biteLocal : I18n.t("guide.about.unknown") }
                        ]

                        Rectangle {
                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitHeight: rowSysLayout.implicitHeight + rootObj.s(20)
                            radius: ThemeBackend.borderRadius
                            color: Qt.alpha(ThemeBackend.surface0, 0.4)
                            border.width: 0

                            RowLayout {
                                id: rowSysLayout
                                anchors.left: parent.left
                                anchors.leftMargin: rootObj.s(14)
                                anchors.right: parent.right
                                anchors.rightMargin: rootObj.s(14)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: rootObj.s(12)

                                IconButton {
                                    enabled: false
                                    size: rootObj.s(32)
                                    Layout.preferredWidth: rootObj.s(32)
                                    Layout.preferredHeight: rootObj.s(32)
                                    Layout.alignment: Qt.AlignVCenter
                                    cornerRadius: ThemeBackend.borderRadius
                                    buttonIcon: modelData.icon
                                    iconFontSize: rootObj.s(16)
                                    accentColor: ThemeBackend.surface0
                                    textColor: "#ffffff"
                                }

                                Text {
                                    text: modelData.label
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(12)
                                    color: ThemeBackend.text
                                    Layout.preferredWidth: rootObj.s(105)
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: modelData.value
                                    font.family: ThemeBackend.fontFamily
                                    font.pixelSize: rootObj.s(12)
                                    color: ThemeBackend.subtext0
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: rootObj.s(12)

                ClickButton {
                    Layout.preferredWidth: rootObj.s(260)
                    Layout.preferredHeight: rootObj.s(42)
                    horizontalPadding: rootObj.s(14)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonText: I18n.t("guide.about.github_repo")
                    textFontSize: rootObj.s(13)
                    buttonIcon: "󰊤"
                    iconFontSize: rootObj.s(16)
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.text

                    onTriggered: Quickshell.execDetached(["xdg-open", "https://github.com/ilyamiro/serpantinum"])
                }

                // ── BITE-OS modification ───────────────────────────────────
                // The distro's own repo, alongside upstream's.
                ClickButton {
                    Layout.preferredWidth: rootObj.s(260)
                    Layout.preferredHeight: rootObj.s(42)
                    horizontalPadding: rootObj.s(14)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonText: "GLITCH-BITE-404/BITE-OS"
                    textFontSize: rootObj.s(13)
                    buttonIcon: "󰊤"
                    iconFontSize: rootObj.s(16)
                    accentColor: ThemeBackend.surface0
                    textColor: ThemeBackend.green

                    onTriggered: Quickshell.execDetached(["xdg-open", "https://github.com/GLITCH-BITE-404/BITE-OS"])
                }
            }
        }
    }
}
