function isFullscreenLike(client) {
    if (!client) return false;
    if (client.fullScreen) return true;
    // Borderless fullscreen: undecorated window covering the whole output
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
