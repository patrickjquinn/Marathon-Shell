import MarathonOS.Shell
import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: diagnosticsWindow

    visible: true
    width: 800
    height: 1000
    title: "Marathon Shell - Internal Diagnostics"
    color: "#1a1a1a"
    Component.onCompleted: {
        console.log("=== MARATHON SHELL DIAGNOSTICS ===");
        console.log("BluetoothManagerCpp available:", typeof BluetoothManagerCpp !== 'undefined');
        if (typeof BluetoothManagerCpp !== 'undefined') {
            console.log("  enabled:", BluetoothManagerCpp.enabled);
            console.log("  available:", BluetoothManagerCpp.available);
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 20
        contentHeight: diagnosticsColumn.height

        Column {
            id: diagnosticsColumn

            width: parent.width
            spacing: 15

            Text {
                text: "╔═══════════════════════════════════════════════════════════╗\n" + "║      Marathon Shell - Internal Service Status         ║\n" + "╚═══════════════════════════════════════════════════════════╝"
                font.family: "monospace"
                font.pixelSize: 14
                color: "#00ff00"
            }

            Rectangle {
                width: parent.width
                height: bluetoothCol.height + 20
                color: "#2a2a2a"
                radius: 5

                Column {
                    id: bluetoothCol

                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 5

                    Text {
                        text: "🔵 BLUETOOTH (BluetoothManagerCpp)"
                        font.pixelSize: 16
                        font.bold: true
                        color: "#00aaff"
                    }

                    Text {
                        text: typeof BluetoothManagerCpp !== 'undefined' ? "✅ Backend available" : "❌ Backend NOT available"
                        font.family: "monospace"
                        color: typeof BluetoothManagerCpp !== 'undefined' ? "#00ff00" : "#ff0000"
                    }

                    Text {
                        text: typeof BluetoothManagerCpp !== 'undefined' ? ("enabled: " + BluetoothManagerCpp.enabled) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof BluetoothManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof BluetoothManagerCpp !== 'undefined' ? ("available: " + BluetoothManagerCpp.available) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof BluetoothManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof BluetoothManagerCpp !== 'undefined' ? ("scanning: " + BluetoothManagerCpp.scanning) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof BluetoothManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof BluetoothManagerCpp !== 'undefined' ? ("adapterName: " + BluetoothManagerCpp.adapterName) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof BluetoothManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof BluetoothManagerCpp !== 'undefined' ? ("paired devices: " + BluetoothManagerCpp.pairedDevices.length) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof BluetoothManagerCpp !== 'undefined'
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: displayCol.height + 20
                color: "#2a2a2a"
                radius: 5

                Column {
                    id: displayCol

                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 5

                    Text {
                        text: "💡 DISPLAY (DisplayManagerCpp)"
                        font.pixelSize: 16
                        font.bold: true
                        color: "#ffaa00"
                    }

                    Text {
                        text: typeof DisplayManagerCpp !== 'undefined' ? "✅ Backend available" : "❌ Backend NOT available"
                        font.family: "monospace"
                        color: typeof DisplayManagerCpp !== 'undefined' ? "#00ff00" : "#ff0000"
                    }

                    Text {
                        text: typeof DisplayManagerCpp !== 'undefined' ? ("brightness: " + DisplayManagerCpp.brightness) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof DisplayManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof DisplayManagerCpp !== 'undefined' ? ("autoBrightnessEnabled: " + DisplayManagerCpp.autoBrightnessEnabled) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof DisplayManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof DisplayManagerCpp !== 'undefined' ? ("available: " + DisplayManagerCpp.available) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof DisplayManagerCpp !== 'undefined'
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: audioCol.height + 20
                color: "#2a2a2a"
                radius: 5

                Column {
                    id: audioCol

                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 5

                    Text {
                        text: "🔊 AUDIO (AudioManagerCpp)"
                        font.pixelSize: 16
                        font.bold: true
                        color: "#ff00aa"
                    }

                    Text {
                        text: typeof AudioManagerCpp !== 'undefined' ? "✅ Backend available" : "❌ Backend NOT available"
                        font.family: "monospace"
                        color: typeof AudioManagerCpp !== 'undefined' ? "#00ff00" : "#ff0000"
                    }

                    Text {
                        text: typeof AudioManagerCpp !== 'undefined' ? ("masterVolume: " + AudioManagerCpp.masterVolume) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof AudioManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof AudioManagerCpp !== 'undefined' ? ("isMuted: " + AudioManagerCpp.isMuted) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof AudioManagerCpp !== 'undefined'
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: networkCol.height + 20
                color: "#2a2a2a"
                radius: 5

                Column {
                    id: networkCol

                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 5

                    Text {
                        text: "📡 NETWORK (NetworkManagerCpp)"
                        font.pixelSize: 16
                        font.bold: true
                        color: "#00ffaa"
                    }

                    Text {
                        text: typeof NetworkManagerCpp !== 'undefined' ? "✅ Backend available" : "❌ Backend NOT available"
                        font.family: "monospace"
                        color: typeof NetworkManagerCpp !== 'undefined' ? "#00ff00" : "#ff0000"
                    }

                    Text {
                        text: typeof NetworkManagerCpp !== 'undefined' ? ("wifiEnabled: " + NetworkManagerCpp.wifiEnabled) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof NetworkManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof NetworkManagerCpp !== 'undefined' ? ("wifiConnected: " + NetworkManagerCpp.wifiConnected) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof NetworkManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof NetworkManagerCpp !== 'undefined' ? ("wifiSsid: " + NetworkManagerCpp.wifiSsid) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof NetworkManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof NetworkManagerCpp !== 'undefined' ? ("signalStrength: " + NetworkManagerCpp.wifiSignalStrength) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof NetworkManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof NetworkManagerCpp !== 'undefined' ? ("available networks: " + NetworkManagerCpp.availableNetworks.length) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof NetworkManagerCpp !== 'undefined'
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: powerCol.height + 20
                color: "#2a2a2a"
                radius: 5

                Column {
                    id: powerCol

                    anchors.centerIn: parent
                    width: parent.width - 20
                    spacing: 5

                    Text {
                        text: "🔋 POWER (PowerManagerCpp)"
                        font.pixelSize: 16
                        font.bold: true
                        color: "#aaff00"
                    }

                    Text {
                        text: typeof PowerManagerCpp !== 'undefined' ? "✅ Backend available" : "❌ Backend NOT available"
                        font.family: "monospace"
                        color: typeof PowerManagerCpp !== 'undefined' ? "#00ff00" : "#ff0000"
                    }

                    Text {
                        text: typeof PowerManagerCpp !== 'undefined' ? ("batteryLevel: " + PowerManagerCpp.batteryLevel + "%") : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof PowerManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof PowerManagerCpp !== 'undefined' ? ("isCharging: " + PowerManagerCpp.isCharging) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof PowerManagerCpp !== 'undefined'
                    }

                    Text {
                        text: typeof PowerManagerCpp !== 'undefined' ? ("isPowerSaveMode: " + PowerManagerCpp.isPowerSaveMode) : ""
                        font.family: "monospace"
                        color: "#ffffff"
                        visible: typeof PowerManagerCpp !== 'undefined'
                    }
                }
            }

            Text {
                text: "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                font.family: "monospace"
                color: "#666666"
            }

            Text {
                text: "C++ Services (NetworkManagerCpp / BluetoothManagerCpp)"
                font.pixelSize: 14
                font.bold: true
                color: "#ffffff"
            }

            Text {
                text: "bluetoothEnabled (C++): " + (typeof BluetoothManagerCpp !== 'undefined' ? BluetoothManagerCpp.enabled : "N/A")
                font.family: "monospace"
                color: "#ffffff"
            }

            Text {
                text: "wifiEnabled (C++): " + (typeof NetworkManagerCpp !== 'undefined' ? NetworkManagerCpp.wifiEnabled : "N/A")
                font.family: "monospace"
                color: "#ffffff"
            }

            Text {
                text: "\nSystemControlStore Status"
                font.pixelSize: 14
                font.bold: true
                color: "#ffffff"
            }

            Text {
                text: "isBluetoothOn: " + (typeof SystemControlStore !== 'undefined' ? SystemControlStore.isBluetoothOn : "N/A")
                font.family: "monospace"
                color: "#ffffff"
            }

            Text {
                text: "brightness: " + (typeof SystemControlStore !== 'undefined' ? SystemControlStore.brightness : "N/A")
                font.family: "monospace"
                color: "#ffffff"
            }

            Text {
                text: "volume: " + (typeof SystemControlStore !== 'undefined' ? SystemControlStore.volume : "N/A")
                font.family: "monospace"
                color: "#ffffff"
            }
        }
    }
}
