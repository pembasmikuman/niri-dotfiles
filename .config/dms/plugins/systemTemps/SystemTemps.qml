import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    minWidth: 260
    minHeight: 300
    widgetWidth: 300
    widgetHeight: 340

    property int cpu: 0
    property int gpu: 0
    property int ssd: 0
    property int cpuUse: 0
    property int gpuUse: 0
    property int ramUsed: 0
    property int ramTotal: 0

    readonly property int ramPercent: ramTotal > 0 ? Math.round(100 * ramUsed / ramTotal) : 0

    // Temperatures (°C) where a reading turns yellow (warn) and red (hot).
    readonly property var limits: ({
        cpu: { warn: 70, hot: 85 },
        gpu: { warn: 70, hot: 83 },
        ssd: { warn: 60, hot: 70 },
        ram: { warn: 80, hot: 90 } // percent used, not °C
    })

    // 0 = normal, 1 = warm, 2 = hot, -1 = no reading (the sensor failed).
    function tempState(kind, c) {
        if (c <= 0) return -1
        if (c >= limits[kind].hot) return 2
        if (c >= limits[kind].warn) return 1
        return 0
    }

    function stateColor(state) {
        switch (state) {
        case 2: return Theme.error
        case 1: return Theme.warning
        case 0: return Theme.success
        default: return Theme.outline
        }
    }

    // Shown in the header, so the same widget names whichever machine it runs on.
    property string hostName: ""

    Process {
        command: ["uname", "-n"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.hostName = text.trim()
        }
    }

    // Prints "cpuT gpuT ssdT cpuUse gpuUse ramUsedMiB ramTotalMiB".
    Process {
        id: reader
        command: ["sh", "-c", "exec \"$HOME/.local/bin/system-temps\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim().split(/\s+/).map(Number)
                if (t.length === 7 && t.every(n => !isNaN(n))) {
                    root.cpu = t[0]
                    root.gpu = t[1]
                    root.ssd = t[2]
                    root.cpuUse = t[3]
                    root.gpuUse = t[4]
                    root.ramUsed = t[5]
                    root.ramTotal = t[6]
                }
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!reader.running) reader.running = true
    }

    // A monochrome SVG tinted to any color.
    component TintedIcon: Item {
        property url source
        property color color: Theme.surfaceText
        Image {
            id: img
            anchors.fill: parent
            source: parent.source
            sourceSize: Qt.size(width, height)
            visible: false
        }
        MultiEffect {
            anchors.fill: img
            source: img
            colorization: 1.0
            colorizationColor: parent.color
        }
    }

    // One part: icon, name, optional usage line and bar (usage < 0 hides both), temperature.
    component PartRow: GridLayout {
        id: part
        property string label
        property string kind
        property url iconSource
        property int temp
        property int usage: -1
        property string detail // replaces the "Usage" line when set (RAM)
        readonly property int state: root.tempState(kind, temp)
        readonly property color tone: root.stateColor(state)

        Layout.fillWidth: true
        columns: 3
        columnSpacing: Theme.spacingM
        rowSpacing: Theme.spacingXS

        TextMetrics {
            id: valueMetrics
            font.family: Theme.monoFontFamily
            font.bold: true
            font.pixelSize: Theme.fontSizeXLarge * 1.3
            text: "100°C"
        }

        Rectangle {
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: width / 2
            color: Theme.withAlpha(Theme.surfaceText, 0.08)
            TintedIcon {
                anchors.centerIn: parent
                width: 20
                height: 20
                source: part.iconSource
                color: Theme.surfaceText
                opacity: 0.8
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: Number.POSITIVE_INFINITY
            spacing: 0
            Text {
                text: part.label
                color: Theme.surfaceText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
            }
            RowLayout {
                visible: part.usage >= 0
                spacing: Theme.spacingS
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Text {
                    // Shrinks with an ellipsis instead of pushing the temperature past the card edge.
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: part.detail !== "" ? part.detail : "Usage: <font face=\"" + Theme.monoFontFamily + "\">" + part.usage + "%</font>"
                    color: Theme.surfaceText
                    opacity: 0.7
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
                // Tag only when this part is over a limit.
                Rectangle {
                    visible: part.state >= 1
                    implicitWidth: tagText.implicitWidth + Theme.spacingM
                    implicitHeight: tagText.implicitHeight + 2
                    radius: Theme.cornerRadiusS
                    color: Theme.withAlpha(part.tone, 0.2)
                    Text {
                        id: tagText
                        anchors.centerIn: parent
                        text: part.state === 2 ? "HOT" : "WARM"
                        color: part.tone
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall * 0.9
                        font.bold: true
                    }
                }
            }
        }

        Text {
            // Reserve room for the widest reading ("100°C") so the column never resizes or clips.
            Layout.preferredWidth: valueMetrics.advanceWidth
            Layout.minimumWidth: valueMetrics.advanceWidth
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: part.temp > 0 ? part.temp + (part.kind === "ram" ? "%" : "°C") : "--"
            color: part.tone
            font.family: Theme.monoFontFamily
            font.bold: true
            font.pixelSize: Theme.fontSizeXLarge * 1.3
        }

        // Usage bar: thin rounded track, filled to the usage percent, same color as the temperature.
        Rectangle {
            visible: part.usage >= 0
            Layout.columnSpan: 3
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: Theme.withAlpha(Theme.surfaceText, 0.1)
            Rectangle {
                width: parent.width * Math.min(Math.max(part.usage, 0), 100) / 100
                height: parent.height
                radius: parent.radius
                color: part.tone
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: Theme.outlineVariant
        opacity: 0.6
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusXL
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.withAlpha(Theme.surfaceText, 0.08)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingL
        spacing: Theme.spacingS

        RowLayout {
            spacing: Theme.spacingM
            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: Theme.cornerRadiusM
                color: Theme.primary
                TintedIcon {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: Qt.resolvedUrl("images/meter.svg")
                    color: Theme.primaryText
                }
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: root.hostName !== "" ? root.hostName : "System"
                    color: Theme.surfaceText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Temperature and usage"
                    color: Theme.surfaceText
                    opacity: 0.7
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        Divider {}
        PartRow { label: "CPU"; kind: "cpu"; iconSource: Qt.resolvedUrl("images/chip.svg"); temp: root.cpu; usage: root.cpuUse }
        Divider { opacity: 0.4 }
        PartRow { label: "GPU"; kind: "gpu"; iconSource: Qt.resolvedUrl("images/gpu.svg"); temp: root.gpu; usage: root.gpuUse }
        Divider { opacity: 0.4 }
        PartRow {
            label: "RAM"; kind: "ram"; iconSource: Qt.resolvedUrl("images/ram.svg")
            temp: root.ramPercent; usage: root.ramPercent
            detail: "Used: <font face=\"" + Theme.monoFontFamily + "\">" + (root.ramUsed / 1024).toFixed(1) + " / " + (root.ramTotal / 1024).toFixed(1) + " GiB</font>"
        }
        Divider { opacity: 0.4 }
        PartRow { label: "SSD"; kind: "ssd"; iconSource: Qt.resolvedUrl("images/ssd.svg"); temp: root.ssd }

        Item { Layout.fillHeight: true }
    }
}
