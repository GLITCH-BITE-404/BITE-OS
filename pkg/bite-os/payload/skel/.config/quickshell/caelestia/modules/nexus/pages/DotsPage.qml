// ─────────────────────────────────────────────────────────────────────────────
//  ◈ BITE-OS  ·  © 2026 GLITCH-BITE-404  ·  // THE SYSTEM BIT YOU
//  https://github.com/GLITCH-BITE-404/BITE-OS
//
//  BITE-OS addition to caelestia-shell. Nexus page that swaps the whole
//  desktop between rices (the shell swaps with it). Port of the old control
//  center's DotsPane to Nexus 2.4.0.
//
//  PageBase takes exactly ONE Item as its content (default property Item
//  contentChild), so the Process/Timer live inside the column, like upstream's
//  AboutPage -- a sibling would fail to load and take the whole shell with it.
//
//  Swapping kills this very shell, so dots-switch.sh runs under `setsid -f`.
// ─────────────────────────────────────────────────────────────────────────────
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Rice & shell")

    property string activeRice: ""
    property string activeShell: "caelestia"
    property bool initialised: false
    property bool swapping: false
    property var rices: []

    function refresh(): void {
        if (!stateReader.running)
            stateReader.running = true;
    }

    function pickRice(target: string): void {
        // vault dir names only; never let anything else reach the shell
        if (!root.initialised || root.swapping || target === root.activeRice || !/^[A-Za-z0-9_-]+$/.test(target))
            return;
        root.swapping = true;
        Quickshell.execDetached(["setsid", "-f", "bash", "-c",
            "\"$HOME/.config/glitch/bin/dots-switch.sh\" " + target + " >/dev/null 2>&1"]);
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: stateReader

            running: true
            command: ["bash", "-c",
                "V=\"$HOME/.local/share/bite-os/rices\"; " +
                "echo \"ACTIVE=$(cat \"$V/.active\" 2>/dev/null)\"; " +
                "echo \"SHELL=$(cat \"$HOME/.local/state/bite-os/active-shell\" 2>/dev/null || echo caelestia)\"; " +
                "for d in \"$V\"/*/; do n=$(basename \"$d\"); case \"$n\" in _*|.*) continue;; esac; echo \"RICE=$n\"; done"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const found = [];
                    for (const l of text.trim().split("\n")) {
                        if (l.startsWith("ACTIVE="))
                            root.activeRice = l.slice(7).trim();
                        else if (l.startsWith("SHELL="))
                            root.activeShell = l.slice(6).trim() || "caelestia";
                        else if (l.startsWith("RICE="))
                            found.push(l.slice(5).trim());
                    }
                    if (JSON.stringify(found) !== JSON.stringify(root.rices))
                        root.rices = found;
                    root.initialised = true;
                }
            }
        }

        Timer {
            interval: 2500
            repeat: true
            running: root.visible
            onTriggered: root.refresh()
        }

        StyledText {
            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.medium
            text: root.swapping ? qsTr("Swapping… the shell restarts in a moment")
                                : qsTr("Active rice: %1  ·  shell: %2").arg(root.activeRice || "?").arg(root.activeShell)
            color: Colours.palette.m3onSurfaceVariant
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.rices

            RowButton {
                required property string modelData
                required property int index
                readonly property bool isActive: modelData === root.activeRice

                first: index === 0
                last: index === root.rices.length - 1
                icon: isActive ? "check_circle" : "swap_horiz"
                text: modelData
                subtext: isActive ? qsTr("Active now") : qsTr("Swap the whole desktop to %1").arg(modelData)
                disabled: isActive || root.swapping || !root.initialised
                onClicked: root.pickRice(modelData)
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.large
            wrapMode: Text.WordWrap
            color: Colours.palette.m3onSurfaceVariant
            text: qsTr("Your current rice is backed up before every swap (~/.local/share/bite-os/rices/_autobackup/). A watchdog reverts to caelestia if the new shell doesn't come up, Super+Ctrl+D flips back from anywhere, and from a TTY: ~/.config/glitch/bin/dots-switch.sh caelestia")
        }
    }
}
