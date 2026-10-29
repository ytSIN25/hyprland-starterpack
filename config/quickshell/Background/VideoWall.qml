import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs.Config
import qs.Services

// Fondo animado: si el fondo actual es un vídeo (Wallpaper.currentIsVideo),
// una ventana por monitor en la capa Background lo reproduce en bucle y sin
// sonido, encima de la imagen de awww (que tiene su primer fotograma).
// Se pausa con el perfil de ahorro de energía o con la pantalla bloqueada.
PanelWindow {
    id: win

    property var modelData
    screen: modelData

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "qs-videowall"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    // Solo dibuja: que nunca reciba clics.
    mask: Region {}

    readonly property bool paused: Power.isSaver || AuthWatch.lockActive

    Video {
        id: video
        anchors.fill: parent
        source: Wallpaper.currentIsVideo ? "file://" + Wallpaper.current : ""
        loops: MediaPlayer.Infinite
        muted: true
        fillMode: VideoOutput.PreserveAspectCrop
        autoPlay: true
        // Funde al entrar para que el cambio desde la imagen no dé un salto.
        opacity: playbackState === MediaPlayer.PlayingState || playbackState === MediaPlayer.PausedState ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
        onSourceChanged: if (source !== "" && !win.paused) play()
    }
    onPausedChanged: paused ? video.pause() : video.play()
}
