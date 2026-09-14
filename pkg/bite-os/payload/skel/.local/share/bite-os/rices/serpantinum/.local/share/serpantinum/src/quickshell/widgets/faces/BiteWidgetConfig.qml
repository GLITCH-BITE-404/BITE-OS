// ◈ BITE-OS addition to serpantinum (upstream AGPL-3.0, (C) Illia Miroshnichenko).
// Shared, live reader for the BITE-OS widgets' own settings file
// (~/.config/serpantinum/bite-widgets.json, rice-managed so it saves with the
// rice). Every BITE-OS face drops one of these in and asks
// `bcfg.get("riceSaves.count", 2)`; edits from the Widgets settings tab apply
// instantly. A missing or broken file just means defaults.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    visible: false
    property var cfg: ({})

    function get(path, fallback) {
        let v = root.cfg;
        const keys = String(path).split(".");
        for (let i = 0; i < keys.length; i++) {
            if (v === null || v === undefined || typeof v !== "object")
                return fallback;
            v = v[keys[i]];
        }
        return (v === undefined || v === null) ? fallback : v;
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/serpantinum/bite-widgets.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const raw = typeof text === "function" ? text() : text;
                root.cfg = (typeof raw === "string" && raw.trim() !== "") ? JSON.parse(raw) : ({});
            } catch (e) {
                root.cfg = ({});
            }
        }
    }
}
