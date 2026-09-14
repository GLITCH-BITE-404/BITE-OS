// ◈ BITE-OS modification of caelestia-shell 2.4.0's lock-screen fetch panel:
// user@host chip, a rotating-quote prompt with a blinking caret, two-tone
// aligned info rows and bordered colour swatches, on 2.4.0's own layout rules
// (fit-to-height thresholds from Tokens.sizes.lock) and 2.4.0 token names.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

StyledRect {
    id: root

    required property real rootHeight

    readonly property bool wide: width > Tokens.sizes.lock.largeFontWidth
    readonly property font monoFont: wide ? Tokens.font.mono.medium : Tokens.font.mono.small
    readonly property string hostName: SysInfo.hostname || Quickshell.env("HOSTNAME") || "bite-os"

    // ── rotating header lines (cursed motivational / glitch flavour) ───────
    readonly property var quotes: [
        "stay hungry. stay cursed.",
        "wake up. rice the world.",
        "root is a state of mind.",
        "we are the ghost in the shell.",
        "404: conformity not found.",
        "compile the void.",
        "bite first. ask never.",
        "the machine is awake. are you?",
        "born to chomp. forged in glitch.",
        "panic() is a feature.",
        "trust no daemon you didn't fork.",
        "low battery, high stakes.",
        "the kernel dreams in violet.",
        "you are the exception.",
        "segfault gracefully.",
        "rm -rf /doubts",
        "grep your reality.",
        "stay weird. stay rooted."
    ]
    property int quoteIndex: Math.floor(Math.random() * quotes.length)

    Timer {
        interval: 7000
        running: root.visible
        repeat: true
        onTriggered: quoteSwap.start()
    }

    SequentialAnimation {
        id: quoteSwap

        PropertyAnimation { target: quoteText; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InOutQuad }
        ScriptAction {
            script: {
                let next = root.quoteIndex;
                while (next === root.quoteIndex && root.quotes.length > 1)
                    next = Math.floor(Math.random() * root.quotes.length);
                root.quoteIndex = next;
            }
        }
        PropertyAnimation { target: quoteText; property: "opacity"; to: 1; duration: 220; easing.type: Easing.InOutQuad }
    }

    implicitHeight: layout.implicitHeight + layout.anchors.topMargin + layout.anchors.margins
    radius: Tokens.rounding.medium
    // fixed alpha + hairline border: readable in leaf mode (no blur backing)
    color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, Colours.transparency.enabled ? 0.55 : 0.92)
    border.width: 1
    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.40)

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraLarge
        anchors.topMargin: Tokens.padding.extraLarge
        anchors.bottomMargin: Tokens.padding.extraLarge

        spacing: Tokens.spacing.small

        // header row 1: user@host chip + small logo (when the big one is hidden)
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: userHost.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: userHost.implicitHeight + Tokens.padding.small * 2

                color: Colours.palette.m3primary
                radius: Tokens.rounding.small

                MonoText {
                    id: userHost

                    anchors.centerIn: parent
                    text: `${SysInfo.user}@${root.hostName}`
                    font.bold: true
                    color: Colours.palette.m3onPrimary
                }
            }

            Item {
                Layout.fillWidth: true
            }

            WrappedLoader {
                Layout.fillHeight: true
                Layout.preferredWidth: height
                Layout.preferredHeight: 0
                active: !iconLoader.active

                sourceComponent: SysInfo.isDefaultLogo ? caelestiaLogo : distroIcon
            }
        }

        // header row 2: full-width quote prompt with a blinking block caret
        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            MonoText {
                text: "~$ "
                color: Colours.palette.m3onSurfaceVariant
            }

            MonoText {
                id: quoteText

                Layout.fillWidth: true
                text: root.quotes[root.quoteIndex]
                color: Colours.palette.m3primary
                font.italic: true
                elide: Text.ElideRight
                wrapMode: Text.NoWrap
            }

            Rectangle {
                implicitWidth: root.monoFont.pointSize * 0.55
                implicitHeight: root.monoFont.pointSize * 1.15
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 2
                color: Colours.palette.m3primary
                radius: 1

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.visible
                    PropertyAnimation { to: 1; duration: 0 }
                    PauseAnimation { duration: 520 }
                    PropertyAnimation { to: 0; duration: 0 }
                    PauseAnimation { duration: 520 }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall
            Layout.bottomMargin: Tokens.spacing.extraSmall
            implicitHeight: 1
            color: Qt.alpha(Colours.palette.m3outline, 0.45)
        }

        // body: logo + two-tone rows, trimmed to fit the lock screen's height
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.extraLarge

            WrappedLoader {
                id: iconLoader

                Layout.fillHeight: true
                active: root.width > Tokens.sizes.lock.largeLogoWidth

                sourceComponent: SysInfo.isDefaultLogo ? caelestiaLogo : distroIcon
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.padding.medium
                Layout.bottomMargin: iconLoader.active || colourRowLoader.active ? Tokens.padding.medium : 0
                spacing: Tokens.spacing.small

                Repeater {
                    model: {
                        const rows = [];
                        const hasBatt = UPower.displayDevice.isLaptopBattery;
                        const h = root.rootHeight;

                        if (!hasBatt && h > Tokens.sizes.lock.fetch4LinesHeight)
                            rows.push({ label: "OS", value: "BITE-OS" });
                        if (h > (hasBatt ? Tokens.sizes.lock.fetch4LinesHeight : Tokens.sizes.lock.fetch3LinesHeight))
                            rows.push({ label: "WM", value: SysInfo.wm });
                        if (!hasBatt || h > Tokens.sizes.lock.fetch3LinesHeight)
                            rows.push({ label: "USR", value: `${SysInfo.user}@${root.hostName}` });
                        if (h > Tokens.sizes.lock.fetch4LinesHeight)
                            rows.push({ label: "SH", value: SysInfo.shell });
                        rows.push({ label: "UP", value: SysInfo.uptime });
                        if (hasBatt)
                            rows.push({ label: "BAT", value: `${[UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state) ? "(+) " : ""}${Math.round(UPower.displayDevice.percentage * 100)}%` });
                        return rows;
                    }

                    FetchRow {
                        required property var modelData

                        label: modelData.label
                        value: modelData.value
                    }
                }
            }
        }

        WrappedLoader {
            id: colourRowLoader

            Layout.topMargin: iconLoader.active ? Tokens.spacing.small : 0
            Layout.alignment: Qt.AlignHCenter
            active: root.rootHeight > Tokens.sizes.lock.showColourBoxRowHeight

            sourceComponent: RowLayout {
                id: coloursRow

                readonly property real box: root.monoFont.pointSize * 1.9

                spacing: Tokens.spacing.small

                Repeater {
                    model: CUtils.clamp(Math.floor((layout.width + coloursRow.spacing) / (coloursRow.box + coloursRow.spacing)), 0, 8)

                    StyledRect {
                        required property int index

                        implicitWidth: implicitHeight
                        implicitHeight: coloursRow.box
                        color: Colours.palette[`term${index}`]
                        radius: Tokens.rounding.extraSmall
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3outline, 0.35)
                    }
                }
            }
        }
    }

    Component {
        id: caelestiaLogo

        Logo {
            width: height
        }
    }

    Component {
        id: distroIcon

        // the BITE-OS mark, from the user's own home (never a hard-coded /home/<name>)
        Image {
            source: "file://" + Quickshell.env("HOME") + "/.config/glitch/icons/logo-hero.png"
            fillMode: Image.PreserveAspectFit
            sourceSize.width: height
            sourceSize.height: height
        }
    }

    component WrappedLoader: Loader {
        asynchronous: true
        visible: active
    }

    // two-tone row: accent label + on-surface value, colon-aligned
    component FetchRow: RowLayout {
        property string label
        property string value

        Layout.fillWidth: true
        spacing: 0

        MonoText {
            // 4-char slot keeps the colons aligned across rows
            text: (parent.label + "    ").substring(0, 4)
            color: Colours.palette.m3primary
            font.bold: true
        }

        MonoText {
            text: ": "
            color: Colours.palette.m3onSurfaceVariant
        }

        MonoText {
            Layout.fillWidth: true
            text: parent.value
            color: Colours.palette.m3onSurface
            font.bold: !Colours.transparency.enabled
            elide: Text.ElideRight
        }
    }

    component MonoText: StyledText {
        font.family: root.monoFont.family
        font.pointSize: root.monoFont.pointSize
    }
}
