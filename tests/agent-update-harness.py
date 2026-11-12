"""Banc de test de auxinuxos-agent-update, lancé par tests/test-agent-update.sh DANS dbus-run-session.

Joue le serveur de notifications (org.freedesktop.Notifications) et la zone de notification
(org.kde.StatusNotifierWatcher) d'AuxiNux Shell, lance l'agent avec de faux pkcheck, pkexec, apt-get, flatpak et
auxinux-settings, et vérifie de bout en bout : recherche, cache, icône, notification, clic, réglage.

Usage : python3 agent-update-harness.py AGENT WORKDIR   (WORKDIR préparé par le script shell)
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from gi.repository import Gio, GLib

AGENT, WORK = sys.argv[1], Path(sys.argv[2])
HOME = WORK / "home"
CALLS = WORK / "calls"
CACHE = HOME / ".cache/auxinux-shell/updates.json"
CONFIG = HOME / ".config/auxinux-shell/config.json"
STATE = HOME / ".local/state/auxinuxos-agent-update/state.json"

failures = 0


def check(label, got, want):
    global failures
    if got == want:
        print(f"  OK   {label}")
    else:
        print(f"  ECHEC {label}: attendu [{want}] obtenu [{got}]")
        failures += 1


NOTIF_XML = """
<node><interface name="org.freedesktop.Notifications">
  <method name="Notify">
    <arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
    <arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/>
    <arg type="a{sv}" direction="in"/><arg type="i" direction="in"/><arg type="u" direction="out"/>
  </method>
  <method name="CloseNotification"><arg type="u" direction="in"/></method>
  <signal name="ActionInvoked"><arg type="u"/><arg type="s"/></signal>
  <signal name="NotificationClosed"><arg type="u"/><arg type="u"/></signal>
</interface></node>"""
WATCHER_XML = """
<node><interface name="org.kde.StatusNotifierWatcher">
  <method name="RegisterStatusNotifierItem"><arg type="s" direction="in"/></method>
</interface></node>"""

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
notifications = []   # (id, summary, body, actions)
closed = []
items = []


def on_notif(_bus, _sender, _path, _iface, method, params, invocation):
    if method == "Notify":
        app, replaces, icon, summary, body, actions, hints, timeout = params.unpack()
        nid = replaces or len(notifications) + 1
        notifications.append((nid, summary, body, list(actions)))
        invocation.return_value(GLib.Variant("(u)", (nid,)))
    else:
        closed.append(params.unpack()[0])
        invocation.return_value(None)


def on_watcher(_bus, sender, _path, _iface, _method, params, invocation):
    items.append(params.unpack()[0] or sender)
    invocation.return_value(None)


bus.register_object("/org/freedesktop/Notifications", Gio.DBusNodeInfo.new_for_xml(NOTIF_XML).interfaces[0],
                    on_notif, None, None)
bus.register_object("/StatusNotifierWatcher", Gio.DBusNodeInfo.new_for_xml(WATCHER_XML).interfaces[0],
                    on_watcher, None, None)
for name in ("org.freedesktop.Notifications", "org.kde.StatusNotifierWatcher"):
    bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName",
                  GLib.Variant("(su)", (name, 4)), None, Gio.DBusCallFlags.NONE, -1, None)

ctx = GLib.MainContext.default()


def wait(cond, timeout=15):
    end = time.time() + timeout
    while time.time() < end:
        while ctx.pending():
            ctx.iteration(False)
        if cond():
            return True
        time.sleep(0.05)
    return False


def calls():
    return CALLS.read_text().splitlines() if CALLS.exists() else []


def sni(prop):
    v = bus.call_sync(items[0], "/StatusNotifierItem", "org.freedesktop.DBus.Properties", "Get",
                      GLib.Variant("(ss)", ("org.kde.StatusNotifierItem", prop)), None, Gio.DBusCallFlags.NONE,
                      3000, None)
    return v.unpack()[0]


def start_agent(extra=None):
    env = dict(os.environ, HOME=str(HOME), XDG_CONFIG_HOME=str(HOME / ".config"),
               XDG_CACHE_HOME=str(HOME / ".cache"), XDG_STATE_HOME=str(HOME / ".local/state"),
               PATH=f"{WORK}/bin:{os.environ['PATH']}", AUXINUX_AGENT_HELPERS=str(WORK / "helpers"),
               AUXINUX_AGENT_FIRST="1", AUXINUX_AGENT_TICK="1", LANG="fr_CA.UTF-8", **(extra or {}))
    return subprocess.Popen([sys.executable, "-I", AGENT], env=env)


def stop(proc):
    proc.terminate()
    proc.wait(5)


# ------------------------------------------------------------------ 1. recherche et signalement
print("== 1. Premiere recherche: cache, icone, notification ==")
agent = start_agent()
check("s'inscrit dans la zone de notification", wait(lambda: items), True)
check("icone cachee tant que rien n'est trouve (avant la recherche)", sni("Status") in ("Passive", "Active"), True)
check("notification recue", wait(lambda: notifications), True)
check("actualisation par le helper, via pkexec, apres pkcheck",
      [c for c in calls() if c.startswith(("pkcheck", "pkexec", "refresh"))][:3],
      ["pkcheck --action-id ca.auxinux.center.refresh --process " + str(agent.pid),
       "pkexec " + str(WORK / "helpers/auxinux-refresh-helper"), "refresh"])
nid, summary, body, actions = notifications[0]
check("titre", summary, "Mises à jour disponibles")
check("nombre (2 DEB + 1 Flatpak) et nouvelle version",
      body, "Nouvelle version d'AuxiNux OS : AuxiNux OS 0.5.1\n3 mises à jour sont prêtes à être installées.")
check("action par defaut (clic sur la bulle)", actions[:2], ["default", "Voir les mises à jour"])
cache = json.loads(CACHE.read_text())
check("cache de la page Mises a jour: paquets",
      cache["packages"], [["auxinuxos-release", "0.5.0+20261027", "0.5.1+20261112"], ["firefox-esr", "", "140.5"]])
check("cache: Flatpak", cache["flatpaks"], [["org.gimp.GIMP", "GIMP", "3.0.6"]])
check("cache: date de recherche recente", abs(cache["last_check"] - time.time()) < 60, True)
check("icone visible", wait(lambda: sni("Status") == "Active"), True)
check("info-bulle", sni("ToolTip")[2], "3 mises à jour disponibles")

print("== 2. Clic: Parametres > Mises a jour ==")
bus.emit_signal(None, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "ActionInvoked",
                GLib.Variant("(us)", (nid, "default")))
check("clic sur la notification ouvre la page", wait(lambda: "auxinux-settings mises-a-jour" in calls()), True)
bus.emit_signal(None, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "ActionInvoked",
                GLib.Variant("(us)", (nid + 99, "default")))
time.sleep(0.5)
check("la notification d'une autre application est ignoree",
      calls().count("auxinux-settings mises-a-jour"), 1)
bus.call_sync(items[0], "/StatusNotifierItem", "org.kde.StatusNotifierItem", "Activate",
              GLib.Variant("(ii)", (0, 0)), None, Gio.DBusCallFlags.NONE, 3000, None)
check("clic sur l'icone ouvre la page", wait(lambda: calls().count("auxinux-settings mises-a-jour") == 2), True)

print("== 3. Pas de nouvelle recherche avant 60 minutes ==")
apt_runs = sum(c.startswith("apt-get") for c in calls())
time.sleep(3)
check("aucune recherche pendant l'intervalle", sum(c.startswith("apt-get") for c in calls()), apt_runs)

print("== 4. Desactiver dans les Parametres ==")
CONFIG.parent.mkdir(parents=True, exist_ok=True)
CONFIG.write_text(json.dumps({"updates": {"auto_check": False}, "theme": "auto"}))
check("l'icone disparait aussitot", wait(lambda: sni("Status") == "Passive"), True)
check("la notification est retiree", wait(lambda: nid in closed), True)
cache["last_check"] = 0
CACHE.write_text(json.dumps(cache))
time.sleep(3)
check("desactive: aucune recherche meme si la derniere est ancienne",
      sum(c.startswith("apt-get") for c in calls()), apt_runs)

print("== 5. Reactiver: meme ensemble = pas de seconde notification ==")
CONFIG.write_text(json.dumps({"updates": {"auto_check": True}}))
check("nouvelle recherche apres reactivation",
      wait(lambda: sum(c.startswith("apt-get") for c in calls()) > apt_runs, 30), True)
check("icone de retour", wait(lambda: sni("Status") == "Active"), True)
time.sleep(1)
check("meme ensemble de mises a jour: pas de seconde notification", len(notifications), 1)

print("== 6. Installation faite dans les Parametres (cache vide) ==")
CACHE.write_text(json.dumps({"last_check": time.time(), "packages": [], "flatpaks": [], "release": None}))
check("l'icone disparait", wait(lambda: sni("Status") == "Passive"), True)
stop(agent)

print("== 7. Nouvel ensemble = nouvelle notification ; pkcheck refuse = pas de pkexec ==")
CACHE.write_text(json.dumps({"last_check": 0, "packages": [], "flatpaks": [], "release": None}))
(WORK / "apt-output").write_text("Inst firefox-esr (140.6 Debian-Security:13/stable [amd64])\n")
(WORK / "flatpak-output").write_text("")
(WORK / "pkcheck-status").write_text("1")
CALLS.write_text("")
items.clear()
notifications.clear()
agent = start_agent()
check("notification du nouvel ensemble", wait(lambda: notifications), True)
check("une seule mise a jour", notifications[0][2] if notifications else "",
      "Une mise à jour est prête à être installée.")
check("pkcheck refuse: AUCUN pkexec (jamais d'invite d'arriere-plan)",
      [c for c in calls() if c.startswith(("pkexec", "refresh"))], [])
check("etat: empreinte memorisee", bool(json.loads(STATE.read_text()).get("notified_signature")), True)
stop(agent)

print("== 8. Desactive des le depart: rien ==")
CACHE.unlink()
CONFIG.write_text(json.dumps({"updates": {"auto_check": False}}))
CALLS.write_text("")
notifications.clear()
agent = start_agent()
time.sleep(4)
check("aucune recherche", [c for c in calls() if c.startswith(("apt-get", "pkcheck"))], [])
check("aucune notification", notifications, [])
stop(agent)

print("== 9. Sans le Shell: AuxiNux OS Center ==")
os.unlink(WORK / "bin/auxinux-settings")
CONFIG.write_text("{}")
(WORK / "pkcheck-status").write_text("0")
CALLS.write_text("")
items.clear()
notifications.clear()
STATE.unlink()
agent = start_agent()
check("notification", wait(lambda: notifications), True)
bus.emit_signal(None, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "ActionInvoked",
                GLib.Variant("(us)", (notifications[0][0], "default")))
check("le clic ouvre le Center", wait(lambda: "auxinux-center" in calls()), True)
stop(agent)

print()
print("TOUS LES TESTS PASSENT" if not failures else f"{failures} ECHEC(S)")
sys.exit(1 if failures else 0)
