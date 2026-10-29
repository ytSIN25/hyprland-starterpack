import QtQuick
import QtQuick.Effects

// SDDM greeter laid out like ~/.config/rofi/type-2/quickshell.rasi:
// wallpaper panel on the left, capsule input + list on the right.
Rectangle {
    id: root
    width: 1920
    height: 1080
    color: cBackground

    // ---- config ---------------------------------------------------------
    function cfg(key, fallback) {
        const v = config[key]
        return (v === undefined || v === null || v === "") ? fallback : v
    }
    readonly property real s: cfg("scale", "auto") === "auto"
                              ? Math.max(1, Math.min(width / 1920, height / 1080) * 1.25)
                              : Number(cfg("scale", 1))
    readonly property string fontFamily: cfg("font", "JetBrainsMono Nerd Font")
    readonly property color cBackground:    cfg("cBackground",    "#E6190f19")
    readonly property color cBackgroundAlt: cfg("cBackgroundAlt", "#CC2d1e2f")
    readonly property color cForeground:    cfg("cForeground",    "#efebf0")
    readonly property color cForegroundDim: cfg("cForegroundDim", "#beb0bf")
    readonly property color cSelected:      cfg("cSelected",      "#e186ea")
    readonly property color cOnSelected:    cfg("cOnSelected",    "#1a1a1a")
    readonly property color cSelectedSoft:  cfg("cSelectedSoft",  "#2Ee186ea")
    readonly property color cBorder:        cfg("cBorder",        "#55e186ea")
    readonly property color cUrgent:        cfg("cUrgent",        "#da6c7b")
    readonly property string wallpaper: Qt.resolvedUrl(cfg("background", "background.jpg"))

    // ---- state ----------------------------------------------------------
    property int userIndex: Math.max(0, userModel.lastIndex)
    property int sessionIndex: Math.max(0, sessionModel.lastIndex)
    property string message: ""
    property bool failed: false

    function currentUserName() {
        const it = users.itemAtIndex(userIndex)
        return it ? it.userName : userModel.lastUser
    }
    function login() {
        message = ""
        failed = false
        busy.running = true
        sddm.login(currentUserName(), password.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            busy.running = false
            failed = true
            message = "  Wrong password — try again"
            password.text = ""
            shake.restart()
            password.forceActiveFocus()
        }
        function onLoginSucceeded() { busy.running = false }
    }

    Timer { id: busy; interval: 100000 }   // only used as a "logging in" flag

    Timer {
        id: clockTick
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            clockTime.text = Qt.formatTime(now, "HH:mm")
            clockDate.text = Qt.formatDate(now, "dddd, d MMMM")
        }
    }

    // ---- background: blurred wallpaper ----------------------------------
    Image {
        id: bgImg
        anchors.fill: parent
        source: root.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: bgImg
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        brightness: -0.12
        saturation: 0.1
        visible: bgImg.status === Image.Ready
    }

    // ---- the card (rofi "window") ---------------------------------------
    Rectangle {
        id: card
        width: 900 * s
        height: 480 * s
        anchors.centerIn: parent
        radius: 22 * s
        color: cBackground
        border.width: 2 * s
        border.color: cBorder

        transform: Translate { id: shakeT }
        SequentialAnimation {
            id: shake
            loops: 2
            NumberAnimation { target: shakeT; property: "x"; to: -10 * s; duration: 45 }
            NumberAnimation { target: shakeT; property: "x"; to: 10 * s; duration: 90 }
            NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 45 }
        }

        Row {
            anchors.fill: parent
            anchors.margins: 12 * s

            // -- left: imagebox ------------------------------------------
            Item {
                id: imagebox
                width: 300 * s
                height: parent.height

                RoundedImage {
                    anchors.fill: parent
                    radius: 16 * s
                    source: root.wallpaper
                }

                // Clock, top-left over the picture
                Column {
                    x: 18 * s; y: 16 * s
                    Text {
                        id: clockTime
                        font.family: fontFamily
                        font.pixelSize: 46 * s
                        font.bold: true
                        color: "white"
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowOpacity: 0.7 }
                    }
                    Text {
                        id: clockDate
                        font.family: fontFamily
                        font.pixelSize: 14 * s
                        color: "white"
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.6; shadowOpacity: 0.8 }
                    }
                }

                // Power "mode-switcher", bottom-left
                Column {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 16 * s
                    spacing: 6 * s

                    Pill {
                        visible: sddm.canSuspend
                        text: "󰤄  Suspend"
                        s: root.s; fontFamily: root.fontFamily
                        cIdle: cBackground; cActive: cSelected; cText: cForegroundDim; cOnActive: cOnSelected
                        onClicked: sddm.suspend()
                    }
                    Pill {
                        visible: sddm.canReboot
                        text: "󰜉  Reboot"
                        s: root.s; fontFamily: root.fontFamily
                        cIdle: cBackground; cActive: cSelected; cText: cForegroundDim; cOnActive: cOnSelected
                        onClicked: sddm.reboot()
                    }
                    Pill {
                        visible: sddm.canPowerOff
                        text: "󰐥  Shut down"
                        s: root.s; fontFamily: root.fontFamily
                        cIdle: cBackground; cActive: cSelected; cText: cForegroundDim; cOnActive: cOnSelected
                        onClicked: sddm.powerOff()
                    }
                }
            }

            // -- right: listbox ------------------------------------------
            Column {
                id: listbox
                width: parent.width - imagebox.width
                height: parent.height
                leftPadding: 18 * s
                rightPadding: 6 * s
                topPadding: 10 * s
                bottomPadding: 6 * s
                spacing: 12 * s
                readonly property real innerW: width - leftPadding - rightPadding

                // inputbar (capsule)
                Rectangle {
                    width: listbox.innerW
                    height: 48 * s
                    radius: height / 2
                    color: cBackgroundAlt
                    border.width: failed ? 1.5 * s : 0
                    border.color: cUrgent

                    Text {
                        id: lockIcon
                        anchors.verticalCenter: parent.verticalCenter
                        x: 18 * s
                        text: "󰌾"
                        font.family: fontFamily
                        font.pixelSize: 16 * s
                        color: failed ? cUrgent : cSelected
                    }

                    TextInput {
                        id: password
                        anchors.left: lockIcon.right
                        anchors.leftMargin: 12 * s
                        anchors.right: hint.left
                        anchors.rightMargin: 12 * s
                        anchors.verticalCenter: parent.verticalCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        font.family: fontFamily
                        font.pixelSize: 15 * s
                        color: cForeground
                        selectionColor: cSelected
                        selectedTextColor: cOnSelected
                        clip: true
                        focus: true
                        cursorDelegate: Rectangle {
                            width: 2 * root.s
                            color: cSelected
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                NumberAnimation { to: 0; duration: 500 }
                                NumberAnimation { to: 1; duration: 500 }
                            }
                        }
                        onTextChanged: if (text.length) failed = false
                        onAccepted: root.login()
                        Keys.onUpPressed: users.decrementCurrentIndex()
                        Keys.onDownPressed: users.incrementCurrentIndex()
                        Keys.onTabPressed: sessionIndex = (sessionIndex + 1) % Math.max(1, sessionModel.count)
                        Keys.onBacktabPressed: sessionIndex = (sessionIndex - 1 + sessionModel.count) % Math.max(1, sessionModel.count)

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Password…"
                            font: password.font
                            color: cForegroundDim
                            visible: !password.text && !password.preeditText
                        }
                    }

                    Text {
                        id: hint
                        anchors.right: parent.right
                        anchors.rightMargin: 18 * s
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: fontFamily
                        font.pixelSize: 13 * s
                        color: keyboard.capsLock ? cUrgent : cForegroundDim
                        text: keyboard.capsLock ? "󰪛 CAPS" : (busy.running ? "…" : "↵")
                    }
                }

                // message
                Rectangle {
                    width: listbox.innerW
                    height: 42 * s
                    radius: 14 * s
                    color: cBackgroundAlt
                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 14 * s
                        anchors.rightMargin: 14 * s
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        font.family: fontFamily
                        font.pixelSize: 14 * s
                        color: failed ? cUrgent : cForeground
                        text: message !== "" ? message
                              : "󰀄  Welcome back" + (sddm.hostName ? " · " + sddm.hostName : "")
                    }
                }

                // listview: users, then sessions
                Item {
                    width: listbox.innerW
                    height: listbox.height - listbox.topPadding - listbox.bottomPadding
                            - 48 * s - 42 * s - 2 * listbox.spacing

                    ListView {
                        id: users
                        width: parent.width
                        height: Math.min(contentHeight, parent.height - sessionsCol.height - 12 * s)
                        model: userModel
                        clip: true
                        spacing: 4 * s
                        currentIndex: root.userIndex
                        onCurrentIndexChanged: root.userIndex = currentIndex
                        keyNavigationWraps: true
                        interactive: contentHeight > height
                        highlightFollowsCurrentItem: false

                        delegate: Rectangle {
                            id: el
                            property string userName: model.name
                            readonly property bool sel: ListView.isCurrentItem
                            width: users.width
                            height: 48 * s
                            radius: 14 * s
                            color: sel ? cSelectedSoft : (hov.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent")

                            // 3px accent bar on the left, like `border: 0 0 0 3px`
                            Rectangle {
                                visible: el.sel
                                width: 3 * s
                                height: parent.height - 2 * radius * 0.6
                                anchors.verticalCenter: parent.verticalCenter
                                radius: width / 2
                                color: cSelected
                            }

                            Item {
                                id: avatar
                                x: 14 * s
                                width: 30 * s; height: 30 * s
                                anchors.verticalCenter: parent.verticalCenter
                                RoundedImage {
                                    id: face
                                    anchors.fill: parent
                                    radius: width / 2
                                    source: model.icon
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: cSelected
                                    visible: face.status !== Image.Ready
                                    Text {
                                        anchors.centerIn: parent
                                        text: (model.realName || model.name).charAt(0).toUpperCase()
                                        font.family: fontFamily
                                        font.pixelSize: 15 * s
                                        font.bold: true
                                        color: cOnSelected
                                    }
                                }
                            }

                            Text {
                                anchors.left: avatar.right
                                anchors.leftMargin: 14 * s
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: fontFamily
                                font.pixelSize: 15 * s
                                font.bold: el.sel
                                color: cForeground
                                text: model.realName || model.name
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 14 * s
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: fontFamily
                                font.pixelSize: 13 * s
                                color: cForegroundDim
                                text: model.realName ? model.name : ""
                            }

                            MouseArea {
                                id: hov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { users.currentIndex = index; password.forceActiveFocus() }
                            }
                        }
                    }

                    // sessions
                    Column {
                        id: sessionsCol
                        width: parent.width
                        anchors.bottom: parent.bottom
                        spacing: 4 * s

                        Text {
                            leftPadding: 14 * s
                            bottomPadding: 2 * s
                            font.family: fontFamily
                            font.pixelSize: 12 * s
                            color: cForegroundDim
                            text: "SESSION  ·  Tab to switch"
                        }

                        Repeater {
                            model: sessionModel
                            delegate: Rectangle {
                                readonly property bool sel: index === root.sessionIndex
                                width: sessionsCol.width
                                height: 40 * s
                                radius: 14 * s
                                color: sel ? cSelectedSoft : (sh.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent")
                                Rectangle {
                                    visible: parent.sel
                                    width: 3 * s
                                    height: parent.height * 0.55
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: width / 2
                                    color: cSelected
                                }
                                Text {
                                    x: 14 * s
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: fontFamily
                                    font.pixelSize: 14 * s
                                    color: parent.sel ? cForeground : cForegroundDim
                                    text: "󰍹  " + model.name
                                }
                                MouseArea {
                                    id: sh
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.sessionIndex = index; password.forceActiveFocus() }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onCompleted: password.forceActiveFocus()
}
