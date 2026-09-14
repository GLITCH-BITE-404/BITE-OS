// ◈ BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia Miroshnichenko).
// Dedsec monitor, Bars look: four LED-segment meters (CPU / RAM / DSK / TMP).
import QtQuick

DedsecFace {
    look: "bars"
    minWidth: 220
    minHeight: 170
    minAspect: 0.8
}
