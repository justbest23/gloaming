function isFullscreenLike(client) {
    if (!client) return false;
    if (client.desktopWindow || client.dock) return false;
    if (client.fullScreen) return true;
    if (!client.normalWindow) return false;
    // A maximized window is not the same thing as fullscreen, even if some
    // window rule strips its border - maximize and fullscreen are distinct
    // KWin states, so explicitly exclude maximized windows here rather than
    // relying on geometry/border alone to tell them apart.
    if (client.maximizeMode !== 0) return false;
    // Borderless fullscreen: undecorated normal window covering the whole output
    var output = client.output;
    if (!output) return false;
    var geo = client.frameGeometry;
    var screenGeo = output.geometry;
    return !client.decorationHasAlpha && client.noBorder &&
           geo.width === screenGeo.width && geo.height === screenGeo.height &&
           geo.x === screenGeo.x && geo.y === screenGeo.y;
}

var inhibitCookie = -1;

function updateForClient(client) {
    var active = isFullscreenLike(client);
    if (active && inhibitCookie === -1) {
        callDBus("org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight",
            "inhibit", function(cookie) { inhibitCookie = cookie; });
    } else if (!active && inhibitCookie !== -1) {
        callDBus("org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight",
            "uninhibit", inhibitCookie);
        inhibitCookie = -1;
    }
}

function watch(client) {
    client.fullScreenChanged.connect(function() { updateForClient(workspace.activeWindow); });
    client.frameGeometryChanged.connect(function() { updateForClient(workspace.activeWindow); });
}

workspace.windowActivated.connect(updateForClient);
workspace.windowAdded.connect(watch);
workspace.windowList().forEach(watch);
updateForClient(workspace.activeWindow);
