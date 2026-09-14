import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import Caelestia.Services

Scope {
    id: root

    readonly property list<var> warnLevels: [...GlobalConfig.general.battery.warnLevels].sort((a, b) => a.level - b.level)
    property real lastPercentage: 100

    function handleBatteryWarnings(): void {
        const p = UPower.displayDevice.percentage * 100;

        if (!UPower.onBattery) {
            root.lastPercentage = p;
            return;
        }

        if (root.lastPercentage >= 0) {
            for (const level of root.warnLevels) {
                if (p <= level.level && root.lastPercentage > level.level) {
                    Toaster.toast(level.title ?? qsTr("Battery warning"), level.message ?? qsTr("Battery level is low"), level.icon ?? "battery_android_alert", level.critical ? Toast.Error : Toast.Warning);
                    break;
                }
            }
        }

        if (!hibernateTimer.running && p <= GlobalConfig.general.battery.criticalLevel) {
            Toaster.toast(qsTr("Hibernating in 5 seconds"), qsTr("Hibernating to prevent data loss"), "battery_android_alert", Toast.Error);
            hibernateTimer.start();
        }

        root.lastPercentage = p;
    }

    // ---- Power profile ↔ OS behaviour ----
    //
    // Performance (rocket): performance over battery. Full effects on —
    //   animations, transparency, blur, shadows, video wallpaper. Kernel
    //   governor goes to performance via power-profiles-daemon, so cores
    //   sit at high clocks ready to absorb anything.
    //
    // Balanced: battery preserved but UI stays snappy. Animations on,
    //   shadows on, but transparency + blur off (those are the expensive
    //   compositor passes on Intel UHD). Video wallpaper kept (~6% CPU
    //   with VAAPI hwdec is fine on balanced). Governor balanced.
    //
    // PowerSaver (leaf): everything stripped for maximum battery life.
    //   No animations, no transparency, no blur, no shadows, no video
    //   wallpaper (mpvpaper killed). Governor powersave.

    function relaunchVideoWallpaperIfNeeded(): void {
        // After leaving PowerSaver, restart mpvpaper if the saved wallpaper
        // is a video so the screen isn't blank.
        Quickshell.execDetached(["bash", "-c",
            "p=$(cat ~/.local/state/hypr/wallpaper 2>/dev/null); " +
            "case \"$p\" in *.mp4|*.webm|*.mkv|*.mov|*.gif) " +
            "pgrep -x mpvpaper >/dev/null || bash ~/.config/hypr/scripts/wallpaper.sh \"$p\" ;; esac"
        ]);
    }

    function applyProfile(): void {
        const p = PowerProfiles.profile;

        if (p === PowerProfile.Performance) {
            GlobalConfig.appearance.anim.durations.scale = 1;
            GlobalConfig.appearance.transparency.enabled = true;
            Quickshell.execDetached(["hyprctl", "keyword", "decoration:blur:enabled", "true"]);
            Quickshell.execDetached(["hyprctl", "keyword", "decoration:shadow:enabled", "true"]);
            Quickshell.execDetached(["hyprctl", "keyword", "animations:enabled", "true"]);
            relaunchVideoWallpaperIfNeeded();
        } else if (p === PowerProfile.PowerSaver) {
            GlobalConfig.appearance.anim.durations.scale = 0;
            GlobalConfig.appearance.transparency.enabled = false;
            Quickshell.execDetached(["hyprctl", "keyword", "decoration:blur:enabled", "false"]);
            Quickshell.execDetached(["hyprctl", "keyword", "decoration:shadow:enabled", "false"]);
            Quickshell.execDetached(["hyprctl", "keyword", "animations:enabled", "false"]);
            Quickshell.execDetached(["pkill", "-x", "mpvpaper"]);
        } else {
            // Balanced
            GlobalConfig.appearance.anim.durations.scale = 1;
            GlobalConfig.appearance.transparency.enabled = false;
            Quickshell.execDetached(["hyprctl", "keyword", "decoration:blur:enabled", "false"]);
            Quickshell.execDetached(["hyprctl", "keyword", "decoration:shadow:enabled", "true"]);
            Quickshell.execDetached(["hyprctl", "keyword", "animations:enabled", "true"]);
            relaunchVideoWallpaperIfNeeded();
        }
    }

    Connections {
        function onProfileChanged(): void {
            root.applyProfile();
        }
        target: PowerProfiles
    }

    Component.onCompleted: applyProfile()

    // ---- Original battery warning + auto-hibernate logic, unchanged ----
    Connections {
        function onOnBatteryChanged(): void {
            if (!UPower.displayDevice.ready)
                return;

            if (UPower.onBattery) {
                if (GlobalConfig.utilities.toasts.chargingChanged)
                    Toaster.toast(qsTr("Charger unplugged"), qsTr("Battery is discharging"), "power_off");
                root.handleBatteryWarnings();
            } else {
                if (GlobalConfig.utilities.toasts.chargingChanged)
                    Toaster.toast(qsTr("Charger plugged in"), qsTr("Battery is charging"), "power");
                root.lastPercentage = 100;
            }
        }

        target: UPower
    }

    Connections {
        function onReadyChanged(): void {
            if (!UPower.displayDevice.ready)
                return;
            root.handleBatteryWarnings();
        }

        target: UPower.displayDevice
    }

    Connections {
        function onPercentageChanged(): void {
            if (!UPower.displayDevice.ready)
                return;
            root.handleBatteryWarnings();
        }

        target: UPower.displayDevice
    }

    Timer {
        id: hibernateTimer

        interval: 5000
        onTriggered: SessionManager.hibernate()
    }
}
