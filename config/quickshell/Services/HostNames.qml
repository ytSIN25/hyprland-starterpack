pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Config

// Quién es una IP, para los avisos del firewall ("Blocked · Samsung"):
//   name:   nombre que da la red (DNS del router con el nombre DHCP del
//           aparato, mDNS, o el DNS inverso si es de Internet)
//   vendor: fabricante por la MAC (solo en la red local, /usr/share/hwdata/oui.txt)
// lookup(ip) es asíncrono; resolved(ip) avisa cuando llega. Caché de 1 h.
Singleton {
    id: root

    signal resolved(string ip)

    property var cache: ({})        // ip → { name, vendor, t }
    property var _queue: []

    // "Samsung", "android-1a2b (Xiaomi)", "" si no se sabe nada
    function label(ip) {
        const c = cache[ip]
        if (!c) return ""
        const name = c.name.length > 32 ? c.name.slice(0, 31) + "…" : c.name
        if (name && c.vendor && name.toLowerCase().indexOf(c.vendor.toLowerCase()) < 0)
            return name + " (" + c.vendor + ")"
        return name || (c.vendor ? I18n.tr("%1 device").arg(c.vendor) : "")
    }

    function lookup(ip) {
        if (!/^[0-9a-fA-F.:]+$/.test(ip)) return
        const c = cache[ip]
        if (c && Date.now() - c.t < 3600000) return
        if (_queue.indexOf(ip) >= 0) return
        _queue = _queue.concat([ip])
        _next()
    }

    function _next() {
        if (proc.running || _queue.length === 0) return
        proc.ip = _queue[0]
        proc.running = true
    }

    // "Samsung Electronics Co.,Ltd" → "Samsung"
    function _shortVendor(v) {
        return (v.split(/[\s,]+/)[0] || "").replace(/\.$/, "")
    }

    Process {
        id: proc
        property string ip: ""
        // La IP va como argumento ($1), nunca dentro del script
        command: ["bash", "-c", `
            name=$(timeout 2 getent hosts "$1" | awk '{print $2; exit}')
            mac=$(ip neigh show "$1" 2>/dev/null | grep -o 'lladdr [0-9a-f:]*' | cut -d' ' -f2)
            # IPv6 de un aparato de casa: el nombre de su IPv4 (misma MAC)
            if [ -z "$name" ] && [ -n "$mac" ]; then
                v4=$(ip -4 neigh | awk -v m="$mac" '$0 ~ "lladdr " m {print $1; exit}')
                [ -n "$v4" ] && name=$(timeout 2 getent hosts "$v4" | awk '{print $2; exit}')
            fi
            vendor=
            if [ -n "$mac" ] && [ -r /usr/share/hwdata/oui.txt ]; then
                oui=$(echo "\${mac:0:8}" | tr 'a-f:' 'A-F-')
                vendor=$(grep -m1 "^$oui" /usr/share/hwdata/oui.txt | cut -f3)
            fi
            printf '%s\\t%s\\n' "$name" "$vendor"`, "hostnames", ip]
        stdout: StdioCollector { id: out }
        onExited: {
            const [name, vendor] = (out.text || "").replace(/\n$/, "").split("\t")
            const c = Object.assign({}, root.cache)
            // getent sin respuesta a veces devuelve la propia IP
            // systemd llama "_gateway" al router
            const n = name === "_gateway" ? I18n.tr("Router") : name
            c[ip] = { name: n && n !== ip ? n.replace(/\.(local|lan|home)$/, "") : "",
                      vendor: root._shortVendor(vendor || ""), t: Date.now() }
            root.cache = c
            root._queue = root._queue.filter(x => x !== ip)
            root.resolved(ip)
            root._next()
        }
    }
}
