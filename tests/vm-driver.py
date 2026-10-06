#!/usr/bin/env python3
"""Pilote de VM QEMU pour les essais d'installation de bout en bout.

Tout passe par QMP (clavier, souris absolue, captures) et par une console
serie en socket UNIX journalisee dans serial.log.

  vm.py start NAME --iso ISO --disk DISK [--size 60G] [--bios] [--mem 6144]
                   [--cpus 6] [--no-cdrom] [--vars FILE] [--net]
  vm.py shot  NAME OUT.png
  vm.py key   NAME COMBO [COMBO...]      ex: ret tab ctrl-alt-t shift-tab
  vm.py type  NAME TEXTE                 disposition US
  vm.py click NAME X Y [--double] [--right]
  vm.py move  NAME X Y
  vm.py eject NAME
  vm.py stop  NAME
  vm.py qmp   NAME JSON
  vm.py sh    NAME COMMANDE [--timeout S]   console serie (shell deja ouvert)
  vm.py send  NAME TEXTE                    ecrit brut sur la console serie
"""
import json
import os
import socket
import subprocess
import sys
import time
import uuid

# En RAM par defaut: QEMU ecrit le journal de la console serie et les
# captures depuis sa boucle principale. Sur un disque d'hote sature, chaque
# octet ecrit pouvait bloquer QEMU -- donc TOUT l'invite (constate le
# 2026-09-29: invite fige sur ldconfig.service pendant treize minutes).
BASE = os.environ.get("E2E_BASE", "/dev/shm/e2e")


def vmdir(name):
    return os.path.join(BASE, name)


class QMP:
    def __init__(self, name):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(os.path.join(vmdir(name), "qmp.sock"))
        self.f = self.s.makefile("rw")
        self.f.readline()
        self.cmd("qmp_capabilities")

    def cmd(self, execute, **args):
        msg = {"execute": execute}
        if args:
            msg["arguments"] = args
        self.f.write(json.dumps(msg) + "\n")
        self.f.flush()
        while True:
            line = self.f.readline()
            if not line:
                raise RuntimeError("QMP ferme")
            r = json.loads(line)
            if "return" in r or "error" in r:
                if "error" in r:
                    raise RuntimeError(json.dumps(r["error"]))
                return r["return"]


US = {}
for c in "abcdefghijklmnopqrstuvwxyz":
    US[c] = [c]
    US[c.upper()] = ["shift", c]
for c in "0123456789":
    US[c] = [c]
PLAIN = {" ": "spc", "-": "minus", "=": "equal", "[": "bracket_left",
         "]": "bracket_right", "\\": "backslash", ";": "semicolon",
         "'": "apostrophe", "`": "grave_accent", ",": "comma", ".": "dot",
         "/": "slash", "\n": "ret", "\t": "tab"}
for c, k in PLAIN.items():
    US[c] = [k]
SHIFTED = {"!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6",
           "&": "7", "*": "8", "(": "9", ")": "0", "_": "minus", "+": "equal",
           "{": "bracket_left", "}": "bracket_right", "|": "backslash",
           ":": "semicolon", '"': "apostrophe", "~": "grave_accent",
           "<": "comma", ">": "dot", "?": "slash"}
for c, k in SHIFTED.items():
    US[c] = ["shift", k]


def keys_of(combo):
    parts = combo.split("-")
    out = []
    for p in parts:
        p = {"enter": "ret", "esc": "esc", "space": "spc", "del": "delete",
             "bs": "backspace", "pgdn": "pgdn", "pgup": "pgup"}.get(p, p)
        out.append({"type": "qcode", "data": p})
    return out


def screen_size(q, tmp):
    q.cmd("screendump", filename=tmp, format="png")
    from PIL import Image
    for _ in range(50):
        try:
            with Image.open(tmp) as im:
                return im.size
        except Exception:
            time.sleep(0.1)
    raise RuntimeError("capture illisible")


def abs_move(q, name, x, y):
    tmp = os.path.join(vmdir(name), ".size.png")
    w, h = screen_size(q, tmp)
    ax = int(x * 32767 / max(w - 1, 1))
    ay = int(y * 32767 / max(h - 1, 1))
    q.cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": ax}},
        {"type": "abs", "data": {"axis": "y", "value": ay}}])


def click(q, name, x, y, button="left", double=False):
    abs_move(q, name, x, y)
    time.sleep(0.15)
    n = 2 if double else 1
    for _ in range(n):
        q.cmd("input-send-event", events=[
            {"type": "btn", "data": {"down": True, "button": button}}])
        time.sleep(0.08)
        q.cmd("input-send-event", events=[
            {"type": "btn", "data": {"down": False, "button": button}}])
        time.sleep(0.12)


def start(name, argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--iso")
    ap.add_argument("--disk", required=True)
    ap.add_argument("--size", default="60G")
    ap.add_argument("--bios", action="store_true")
    ap.add_argument("--mem", default="6144")
    ap.add_argument("--cpus", default="6")
    ap.add_argument("--no-cdrom", action="store_true")
    ap.add_argument("--vars")
    ap.add_argument("--nonet", action="store_true")
    ap.add_argument("--vga", default="virtio")
    ap.add_argument("--diskif", default="nvme")
    a = ap.parse_args(argv)
    d = vmdir(name)
    os.makedirs(d, exist_ok=True)
    if not os.path.exists(a.disk):
        subprocess.check_call(["qemu-img", "create", "-f", "raw", a.disk, a.size])
    # noreboot: le chien de garde TCO emule redemarre la VM quand le noyau
    # invite, sature par l'emulation, ne le relance pas a temps -- constate le
    # 2026-09-29 en pleine installation. Artefact de TCG, pas du systeme teste.
    args = ["qemu-system-x86_64", "-machine", "q35", "-global", "ICH9-LPC.noreboot=true",
            "-accel", "tcg,thread=multi",
            "-cpu", "max", "-m", a.mem, "-smp", a.cpus,
            "-display", "none",
            "-qmp", "unix:%s/qmp.sock,server=on,wait=off" % d,
            "-chardev", "socket,id=s0,path=%s/serial.sock,server=on,wait=off,"
                        "logfile=%s/serial.log,logappend=on" % (d, d),
            "-serial", "chardev:s0",
            # AUXINUX_VM_RTC=base=2026-01-01: horloge materielle fausse, comme
            # une pile CMOS morte -- seul moyen de voir en VM les pannes HTTPS
            # d'une machine dont l'heure n'est pas synchronisee.
            "-rtc", os.environ.get("AUXINUX_VM_RTC", "base=utc"),
            "-device", "qemu-xhci", "-device", "usb-tablet",
            "-pidfile", "%s/qemu.pid" % d]
    if a.vga == "virtio":
        args += ["-device", "virtio-vga"]
    else:
        args += ["-vga", a.vga]
    if not a.nonet:
        args += ["-netdev", "user,id=n0", "-device", "virtio-net-pci,netdev=n0"]
    # detect-zeroes=unmap: le fichier d'echange (des Go de zeros) ne coute
    # aucune ecriture sur l'hote, dont le RAID5 mecanique sature vite.
    dopts = "format=raw,cache=unsafe,aio=threads,discard=unmap,detect-zeroes=unmap"
    if a.diskif == "nvme":
        args += ["-drive", "file=%s,if=none,id=d0,%s" % (a.disk, dopts),
                 "-device", "nvme,serial=AUXE2E0001,drive=d0,bootindex=1"]
    elif a.diskif == "sata":
        args += ["-drive", "file=%s,if=none,id=d0,%s" % (a.disk, dopts),
                 "-device", "ide-hd,drive=d0,bus=ide.0,bootindex=1"]
    else:
        args += ["-drive", "file=%s,if=virtio,%s" % (a.disk, dopts)]
    if a.iso and not a.no_cdrom:
        # Le lecteur passe APRES le disque, comme sur un PC dont le disque
        # interne est le premier peripherique d'amorcage: le live demarre tant
        # que le disque est vide, puis le systeme installe demarre seul apres
        # « Terminé », media encore insere -- le cas le plus courant.
        args += ["-drive", "file=%s,format=raw,if=none,id=cd0,media=cdrom,readonly=on" % a.iso,
                 "-device", "ide-cd,drive=cd0,bus=ide.2,bootindex=2"]
    if not a.bios:
        vars_file = a.vars or os.path.join(d, "OVMF_VARS.fd")
        if not os.path.exists(vars_file):
            subprocess.check_call(["cp", "/usr/share/OVMF/OVMF_VARS_4M.fd", vars_file])
        args += ["-drive", "if=pflash,format=raw,unit=0,readonly=on,"
                           "file=/usr/share/OVMF/OVMF_CODE_4M.fd",
                 "-drive", "if=pflash,format=raw,unit=1,file=%s" % vars_file]
    with open(os.path.join(d, "cmdline"), "w") as f:
        f.write(" ".join(args) + "\n")
    log = open(os.path.join(d, "qemu.log"), "a")
    p = subprocess.Popen(args, stdout=log, stderr=log, stdin=subprocess.DEVNULL,
                         start_new_session=True)
    time.sleep(2)
    if p.poll() is not None:
        print(open(os.path.join(d, "qemu.log")).read())
        sys.exit(1)
    print("pid", p.pid)


def serial_lock(name):
    """Une seule conversation a la fois sur la console serie: deux clients
    simultanes y entrelacent leurs caracteres, et le shell root de la VM
    execute alors un melange des deux commandes."""
    import fcntl
    f = open(os.path.join(vmdir(name), "serial.lock"), "w")
    fcntl.flock(f, fcntl.LOCK_EX)
    return f


def serial_send(name, text):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(os.path.join(vmdir(name), "serial.sock"))
    for ch in text:
        s.send(ch.encode())
        time.sleep(0.002)
    time.sleep(0.2)
    s.close()


def serial_sh(name, command, timeout):
    log = os.path.join(vmdir(name), "serial.log")
    start_size = os.path.getsize(log) if os.path.exists(log) else 0
    mark = "E2E" + uuid.uuid4().hex[:10]
    # Le marqueur est reconstruit par le shell: l'echo de la commande tapee ne
    # contient donc jamais la chaine finale, seule la sortie la contient.
    line = "%s; echo %s''%s rc=$?\r" % (command, mark[:5], mark[5:])
    serial_send(name, line)
    t0 = time.time()
    while time.time() - t0 < timeout:
        with open(log, "rb") as f:
            f.seek(start_size)
            data = f.read().decode("utf-8", "replace")
        if (mark + " rc=") in data:
            out = data.split(mark + " rc=")[0]
            rc = data.split(mark + " rc=")[1].split()[0] if data.split(mark + " rc=")[1].split() else "?"
            # Retire la ligne de commande renvoyee en echo.
            lines = out.split("\n")
            if lines and mark[:5] in lines[0]:
                lines = lines[1:]
            print("\n".join(lines).replace("\r", ""))
            print("[rc=%s]" % rc)
            return
        time.sleep(0.5)
    with open(log, "rb") as f:
        f.seek(start_size)
        print(f.read().decode("utf-8", "replace").replace("\r", ""))
    print("[TIMEOUT]")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(64)
    op, name, rest = sys.argv[1], sys.argv[2], sys.argv[3:]
    if op == "start":
        return start(name, rest)
    if op == "send":
        lk = serial_lock(name)
        return serial_send(name, rest[0].encode().decode("unicode_escape"))
    if op == "sh":
        timeout = 60
        if "--timeout" in rest:
            i = rest.index("--timeout")
            timeout = float(rest[i + 1])
            del rest[i:i + 2]
        lk = serial_lock(name)
        return serial_sh(name, rest[0], timeout)
    q = QMP(name)
    if op == "shot":
        out = os.path.abspath(rest[0])
        q.cmd("screendump", filename=out, format="png")
        time.sleep(0.5)
        print(out)
    elif op == "key":
        for combo in rest:
            q.cmd("send-key", keys=keys_of(combo))
            time.sleep(0.15)
    elif op == "type":
        for ch in rest[0]:
            if ch not in US:
                raise SystemExit("caractere non gere: %r" % ch)
            # Appui bref: sur un invite lent, 100 ms (le defaut de QEMU)
            # declenchent la repetition automatique de la touche.
            q.cmd("send-key", keys=[{"type": "qcode", "data": k} for k in US[ch]],
                  **{"hold-time": 25})
            time.sleep(0.12)
    elif op == "click":
        x, y = int(rest[0]), int(rest[1])
        click(q, name, x, y, button="right" if "--right" in rest else "left",
              double="--double" in rest)
    elif op == "move":
        abs_move(q, name, int(rest[0]), int(rest[1]))
    elif op == "eject":
        # « device » designe le lecteur par le nom de son support (-drive id=).
        print(q.cmd("eject", device="cd0", force=True))
    elif op == "stop":
        try:
            q.cmd("quit")
        except Exception:
            pass
    elif op == "qmp":
        m = json.loads(rest[0])
        print(json.dumps(q.cmd(m["execute"], **m.get("arguments", {})), indent=1))
    else:
        print(__doc__)
        sys.exit(64)


if __name__ == "__main__":
    main()
