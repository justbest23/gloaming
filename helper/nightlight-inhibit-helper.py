#!/usr/bin/env python3
# nightlight-inhibit-helper.py
# D-Bus-activated helper that inhibits/uninhibits KWin Night Light on behalf
# of the nightcolor-fullscreen-inhibit KWin script.
#
# Why this exists: KWin's JS callDBus() marshals every JS number as int32
# (KDE bug 486024, fix MR plasma/kwin!5695 still unmerged as of 6.7.2), so a
# script can call uninhibit(uint cookie) but the call never dispatches -
# "Could not find slot NightLightAdaptor::uninhibit" - leaving the inhibit
# stuck until the compositor restarts. KWin also keys inhibit cookies to the
# caller's bus connection, so no other process can release them. Routing both
# calls through this helper gives them a real uint32 signature, and if the
# helper ever dies while inhibiting, KWin's service watcher releases the
# inhibit automatically instead of leaving it stuck.

import os
import re

import gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

BUS_NAME = "org.duskwatch.NightLightInhibit"
OBJECT_PATH = "/org/duskwatch/NightLightInhibit"
CONFIG_FILE = os.path.join(
    os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")),
    "duskwatch", "duskwatch.conf")

INTROSPECTION_XML = """
<node>
  <interface name="org.duskwatch.NightLightInhibit">
    <method name="SetInhibited">
      <arg type="b" name="inhibited" direction="in"/>
    </method>
    <method name="SetFullscreenOutputs">
      <arg type="s" name="outputs" direction="in"/>
    </method>
    <property name="FullscreenOutputs" type="s" access="read"/>
  </interface>
</node>
"""

session_bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
cookie = None
# Comma-joined connector names with a fullscreen window ("DP-2,HDMI-A-1"),
# "*" for "all outputs" (legacy SetInhibited callers, which can't say which
# output), "" for none. Republished as the FullscreenOutputs property so
# fullscreen-brightness-watch.sh can brighten just the affected screens.
fullscreen_outputs = ""


def call_nightlight(method, params=None):
    return session_bus.call_sync(
        "org.kde.KWin", "/org/kde/KWin/NightLight", "org.kde.KWin.NightLight",
        method, params, None, Gio.DBusCallFlags.NONE, 5000, None)


def set_inhibited(inhibited):
    global cookie
    if inhibited and cookie is None:
        cookie = call_nightlight("inhibit").unpack()[0]
    elif not inhibited and cookie is not None:
        try:
            call_nightlight("uninhibit", GLib.Variant("(u)", (cookie,)))
        finally:
            # A stale cookie (e.g. after a compositor restart) is a server-side
            # no-op; never let it wedge the helper in the inhibited state.
            cookie = None


def pause_outputs():
    """NIGHTCOLOR_PAUSE_OUTPUTS from duskwatch.conf: which outputs' fullscreen
    windows pause Night Color. Returns None for "all screens trigger it"
    (unset, empty, or the literal "all" - the default), else a set of
    connector names. Re-read on every fullscreen change so config edits
    apply without restarting this helper."""
    try:
        with open(CONFIG_FILE) as f:
            text = f.read()
    except OSError:
        return None
    matches = re.findall(r"^NIGHTCOLOR_PAUSE_OUTPUTS=(.*)$", text, re.MULTILINE)
    if not matches:
        return None
    val = matches[-1].strip().strip('"')  # last assignment wins, like the shell loader
    if not val or val == "all":
        return None
    return {c for c in re.split(r"[,\s]+", val) if c}


def should_inhibit(outputs):
    if not outputs:
        return False
    allowed = pause_outputs()
    # "*" is the legacy SetInhibited channel: no output info, so it always
    # triggers. The pause itself is compositor-global either way - KWin has
    # no per-output color temperature; this only picks which screens'
    # fullscreen windows are allowed to trigger it.
    if allowed is None or outputs == "*":
        return True
    return any(o in allowed for o in outputs.split(","))


def set_fullscreen_outputs(outputs):
    global fullscreen_outputs
    if outputs == fullscreen_outputs:
        return
    fullscreen_outputs = outputs
    # Publish the new set before touching Night Light, so brightness keeps
    # working even if the NightLight interface is unavailable and the inhibit
    # call below fails.
    session_bus.emit_signal(
        None, OBJECT_PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
        GLib.Variant("(sa{sv}as)", (
            "org.duskwatch.NightLightInhibit",
            {"FullscreenOutputs": GLib.Variant("s", fullscreen_outputs)},
            [],
        )))
    set_inhibited(should_inhibit(fullscreen_outputs))


def handle_method_call(connection, sender, path, interface, method, params, invocation):
    if method == "SetFullscreenOutputs":
        try:
            set_fullscreen_outputs(params.unpack()[0])
            invocation.return_value(None)
        except GLib.Error as e:
            invocation.return_dbus_error("org.duskwatch.NightLightInhibit.Error", str(e))
    elif method == "SetInhibited":
        # Legacy boolean form (pre-per-screen KWin script): no output info,
        # so treat it as "all outputs".
        try:
            set_fullscreen_outputs("*" if params.unpack()[0] else "")
            invocation.return_value(None)
        except GLib.Error as e:
            invocation.return_dbus_error("org.duskwatch.NightLightInhibit.Error", str(e))
    else:
        invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)


def handle_get_property(connection, sender, path, interface, prop):
    if prop == "FullscreenOutputs":
        return GLib.Variant("s", fullscreen_outputs)
    return None


node_info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
session_bus.register_object(OBJECT_PATH, node_info.interfaces[0], handle_method_call,
                            handle_get_property, None)

loop = GLib.MainLoop()
Gio.bus_own_name_on_connection(session_bus, BUS_NAME, Gio.BusNameOwnerFlags.NONE,
                               None, lambda *a: loop.quit())
loop.run()
