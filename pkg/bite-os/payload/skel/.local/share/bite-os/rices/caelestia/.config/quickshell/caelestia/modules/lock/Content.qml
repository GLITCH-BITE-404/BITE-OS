import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

RowLayout {
    id: root

    required property var lock

    spacing: Tokens.spacing.largeIncreased * 2

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        WeatherInfo {
            Layout.fillWidth: true
            rootHeight: root.height
        }

        Fetch {
            Layout.fillWidth: true
            rootHeight: root.height
        }

        Media {
            Layout.fillWidth: true
            Layout.fillHeight: true
            lock: root.lock
        }
    }

    Center {
        lock: root.lock
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        Resources {
            Layout.fillWidth: true
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true

            bottomRightRadius: Tokens.rounding.extraLarge
            radius: Tokens.rounding.medium
            // BITE-OS: fixed alpha + hairline border so the lock panels stay
            // readable in leaf mode (transparency off, no blur backing)
            color: Qt.alpha(Colours.palette.m3surfaceContainer, Colours.transparency.enabled ? 0.55 : 0.92)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.40)

            NotifDock {
                lock: root.lock
            }
        }
    }
}
