pragma Singleton
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../"
import "../reusables"

QtObject {
    id: registry

    property var componentCache: ({})

    property Component defaultToolbarButtonComponent: Component {
        ColumnLayout {
            id: itemCol
            property var typeData: null
            property var redactor: null

            spacing: Scaler.s(6)
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Scaler.s(52)

            IconButton {
                size: Scaler.s(48)
                iconOffsetX: (itemCol.typeData && itemCol.typeData.iconOffsetX !== undefined) ? Scaler.s(itemCol.typeData.iconOffsetX) : 0
                cornerRadius: ThemeBackend.borderRadius
                buttonIcon: (itemCol.typeData && itemCol.typeData.icon) ? itemCol.typeData.icon : ""
                iconFontSize: Scaler.s(22)
                accentColor: ThemeBackend.surface0
                textColor: ThemeBackend.text
                Layout.alignment: Qt.AlignHCenter

                onClicked: {
                    if (itemCol.redactor && itemCol.typeData) {
                        itemCol.redactor.addWidget(itemCol.typeData.id);
                    }
                }
            }

            Text {
                text: (itemCol.typeData && itemCol.typeData.name) ? itemCol.typeData.name : (itemCol.typeData ? itemCol.typeData.id : "")
                font.family: ThemeBackend.fontFamily
                font.pixelSize: Scaler.s(11)
                font.bold: true
                color: ThemeBackend.subtext0
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Scaler.s(52)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                Layout.bottomMargin: Scaler.s(2)
            }
        }
    }

    readonly property var types: ({
        "visualizer": {
            name: I18n.t("widgets.types.visualizer"),
            icon: "󰎈",
            iconOffsetX: 0,
            defaultWidth: Math.round((Quickshell.screens && Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1920) / 2),
            defaultHeight: 180,
            defaultVariant: "bars",
            variants: {
                "bars": { file: "faces/VisualizerFace.qml", icon: "1", label: I18n.t("widgets.variants.bars") },
                "continuous": { file: "faces/VisualizerFaceContinuous.qml", icon: "2", label: I18n.t("widgets.variants.continuous") }
            },
            additionalSettings: [
                {
                    id: "stretchWidth",
                    icon: "󰊓",
                    iconFontSize: 16,
                    action: "stretchWidth",
                    row: "top",
                    accentColor: "surface0",
                    textColor: "mauve"
                }
            ]
        },
        "time": {
            name: I18n.t("widgets.types.clock"),
            icon: "󰥔",
            defaultWidth: 250,
            iconOffsetX: -1,
            defaultHeight: 120,
            defaultVariant: "digital",
            variants: {
                "digital": { file: "faces/ClockFaceDigital.qml", icon: "1", label: I18n.t("widgets.variants.digital") },
                "analog":  { file: "faces/ClockFaceAnalog.qml",  icon: "2", label: I18n.t("widgets.variants.analog")  },
                "minimal": { file: "faces/ClockFaceMinimal.qml", icon: "3", label: I18n.t("widgets.variants.minimal") }
            },
            additionalSettings: [
                {
                    id: "stretchWidth",
                    icon: "󰊓",
                    iconFontSize: 16,
                    action: "stretchWidth",
                    row: "top",
                    accentColor: "surface0",
                    textColor: "mauve"
                }
            ]
        },
        "music": {
            name: I18n.t("widgets.types.music"),
            icon: "󰎈",
            defaultWidth: 340,
            defaultHeight: 120,
            defaultVariant: "full",
            variants: {
                "full": { file: "faces/MusicFace.qml", icon: "1", label: I18n.t("widgets.variants.full") },
                "round": { file: "faces/MusicFaceRound.qml", icon: "2", label: I18n.t("widgets.variants.round") }
            },
            additionalSettings: [
                {
                    id: "stretchWidth",
                    icon: "󰊓",
                    iconFontSize: 16,
                    action: "stretchWidth",
                    row: "top",
                    accentColor: "surface0",
                    textColor: "mauve"
                }
            ]
        },
        "weather": {
            name: I18n.t("widgets.types.weather"),
            icon: "󰖐",
            iconOffsetX: -4,
            defaultWidth: 250,
            defaultHeight: 120,
            defaultVariant: "compact",
            variants: {
                "compact": { file: "faces/WeatherFaceCompact.qml", icon: "1", label: I18n.t("widgets.variants.compact") },
                "full": { file: "faces/WeatherFaceFull.qml", icon: "2", label: I18n.t("widgets.variants.full") },
                "round": { file: "faces/WeatherFaceRound.qml", icon: "3", label: I18n.t("widgets.variants.round") }
            },
            additionalSettings: [
                {
                    id: "stretchWidth",
                    icon: "󰊓",
                    iconFontSize: 16,
                    action: "stretchWidth",
                    row: "top",
                    accentColor: "surface0",
                    textColor: "mauve"
                }
            ]
        },
        "image": {
            name: I18n.t("widgets.types.image"),
            icon: "󰋩",
            iconOffsetX: -1,
            defaultWidth: 300,
            defaultHeight: 200,
            defaultVariant: "rect",
            requiresFilePicker: true,
            variants: {
                "rect": { file: "faces/ImageFaceRect.qml", icon: "1", label: I18n.t("widgets.variants.rect") },
                "rounded": { file: "faces/ImageFaceRounded.qml", icon: "2", label: I18n.t("widgets.variants.rounded") },
                "round": { file: "faces/ImageFaceRound.qml", icon: "3", label: I18n.t("widgets.variants.round") }
            },
            additionalSettings: [
                {
                    id: "pickImage",
                    icon: "󰋩",
                    iconFontSize: 16,
                    action: "pickImage",
                    row: "top",
                    accentColor: "surface0",
                    textColor: "mauve"
                },
                {
                    id: "stretchWidth",
                    icon: "󰊓",
                    iconFontSize: 16,
                    action: "stretchWidth",
                    row: "top",
                    accentColor: "surface0",
                    textColor: "mauve"
                }
            ]
        },
        "user": {
            name: I18n.t("widgets.types.user"),
            icon: "",
            iconOffsetX: 0,
            defaultWidth: 260,
            defaultHeight: 140,
            defaultVariant: "default",
            variants: {
                "default": { file: "faces/UserFace.qml", icon: "1", label: I18n.t("widgets.variants.default") }
            }
        },
        "usage": {
            name: I18n.t("widgets.types.usage"),
            icon: "󰍛",
            iconOffsetX: -1,
            defaultWidth: 400,
            defaultHeight: 350,
            defaultVariant: "default",
            variants: {
                "default": { file: "faces/UsageFace.qml", icon: "1", label: I18n.t("widgets.variants.default") }
            }
        },
        "battery": {
            name: I18n.t("widgets.types.battery"),
            icon: "󰁹",
            iconOffsetX: 1,
            defaultWidth: 260,
            defaultHeight: 90,
            defaultVariant: "default",
            variants: {
                "default": { file: "faces/BatteryFace.qml", icon: "1", label: I18n.t("widgets.variants.default") }
            }
        },
        // ── BITE-OS modification: our own widget faces (plain names: I18n.t
        // has no fallback, and these would otherwise need 10 language files)
        "dedsec": {
            name: "Dedsec monitor",
            biteos: true,
            icon: String.fromCodePoint(0xF018D),
            iconOffsetX: 0,
            defaultWidth: 380,
            defaultHeight: 230,
            defaultVariant: "default",
            variants: {
                "default": { file: "faces/DedsecFace.qml", icon: "1", label: "Terminal" },
                "bars": { file: "faces/DedsecBarsFace.qml", icon: "2", label: "Bars" },
                "hex": { file: "faces/DedsecHexFace.qml", icon: "3", label: "Hex" }
            }
        },
        "matrix": {
            name: "Matrix rain",
            biteos: true,
            icon: String.fromCodePoint(0xF0628),
            iconOffsetX: 0,
            defaultWidth: 320,
            defaultHeight: 240,
            defaultVariant: "default",
            variants: {
                "default": { file: "faces/MatrixFace.qml", icon: "1", label: "Katakana" },
                "binary": { file: "faces/MatrixBinaryFace.qml", icon: "2", label: "Binary" },
                "glitch": { file: "faces/MatrixGlitchFace.qml", icon: "3", label: "Glitch" }
            }
        },
        "rice": {
            name: "Rice switcher",
            biteos: true,
            icon: String.fromCodePoint(0xF03D8),
            iconOffsetX: 0,
            defaultWidth: 300,
            defaultHeight: 190,
            defaultVariant: "default",
            variants: {
                "default": { file: "faces/RiceFace.qml", icon: "1", label: "Cards" },
                "compact": { file: "faces/RiceCompactFace.qml", icon: "2", label: "Compact" }
            }
        },
        "ricesaves": {
            name: "Rice saves",
            biteos: true,
            icon: String.fromCodePoint(0xF02DA),
            iconOffsetX: 0,
            defaultWidth: 300,
            defaultHeight: 200,
            defaultVariant: "default",
            variants: {
                "default": { file: "faces/RiceSavesFace.qml", icon: "1", label: "List" }
            }
        },
        "widgetsaves": {
            name: "Widget layouts",
            biteos: true,
            icon: String.fromCodePoint(0xF0570),
            iconOffsetX: 0,
            defaultWidth: 320,
            defaultHeight: 220,
            defaultVariant: "default",
            variants: {
                "default": { file: "faces/WidgetSavesFace.qml", icon: "1", label: "List" }
            }
        },
        "workspacemap": {
            name: "Workspace map",
            biteos: true,
            icon: String.fromCodePoint(0xF0A07),
            iconOffsetX: 0,
            defaultWidth: 420,
            defaultHeight: 180,
            defaultVariant: "default",
            variants: {
                "default": { file: "faces/WorkspaceMapFace.qml", icon: "1", label: "Grid" }
            }
        },
        "proctop": {
            name: "Process top",
            biteos: true,
            icon: String.fromCodePoint(0xF0128),
            iconOffsetX: 0,
            defaultWidth: 400,
            defaultHeight: 230,
            defaultVariant: "default",
            variants: {
                "default": { file: "faces/ProcTopFace.qml", icon: "1", label: "Terminal" }
            }
        }
    })

    function toolbarComponent(type) {
        let t = types[type];
        if (t && t.toolbarComponent) {
            return t.toolbarComponent;
        }
        return defaultToolbarButtonComponent;
    }

    function faceFile(type, variant) {
        let t = types[type];
        if (!t) return "";
        let v = t.variants[variant] || t.variants[t.defaultVariant];
        return v ? Qt.resolvedUrl(v.file) : "";
    }

    function faceComponent(type, variant) {
        let t = types[type];
        if (!t) return null;
        let vKey = (variant && t.variants && t.variants[variant]) ? variant : t.defaultVariant;
        let cacheKey = type + "_" + vKey;
        if (componentCache[cacheKey]) {
            return componentCache[cacheKey];
        }
        let fileUrl = faceFile(type, vKey);
        if (!fileUrl) return null;
        let comp = Qt.createComponent(fileUrl);
        if (comp) {
            componentCache[cacheKey] = comp;
        }
        return comp;
    }

    function variantList(type) {
        let t = types[type];
        if (!t || !t.variants) return [];
        return Object.keys(t.variants).map(k => Object.assign({ id: k }, t.variants[k]));
    }

    function defaultVariant(type) {
        return types[type] ? types[type].defaultVariant : "";
    }

    function defaultSize(type) {
        let t = types[type];
        if (!t) return { w: 250, h: 120 };
        return {
            w: t.defaultWidth || 250,
            h: t.defaultHeight || 120
        };
    }

    function typeList() {
        return Object.keys(types).map(k => Object.assign({ id: k }, types[k]));
    }

    function additionalSettings(type, row) {
        let t = types[type];
        if (!t || !t.additionalSettings) return [];
        if (!row) return t.additionalSettings;
        return t.additionalSettings.filter(s => (s.row || "top") === row);
    }
}
