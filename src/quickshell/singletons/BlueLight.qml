pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root

    readonly property string compositor: {
        let de = (typeof SystemInfo !== "undefined" && SystemInfo.desktopEnv) ? SystemInfo.desktopEnv.toLowerCase() : "";
        if (de.indexOf("niri") !== -1) return "niri";
        if (de.indexOf("sway") !== -1) return "sway";
        return "hyprland";
    }

    property var defaultDisplaySettings: ({ "monitors": {} })

    function getCoordinates() {
        let lat = 0;
        let lon = 0;

        if (typeof Location !== "undefined") {
            lat = Location.latitude;
            lon = Location.longitude;
        }

        if (lat === 0 && lon === 0) {
            let genSet = Config.getSetting("general", {});
            let loc = genSet.location || {};
            if (loc.latitude !== undefined) lat = Number(loc.latitude);
            if (loc.longitude !== undefined) lon = Number(loc.longitude);
        }

        if (lat === 0 && lon === 0) {
            console.warn("BlueLight: location unset — auto schedule will use Null Island as reference and won't match your real sunrise/sunset. Set location in Settings.");
        }

        return { "lat": lat, "lon": lon };
    }

    function kelvinFromTemp(temp) {
        let t = (temp !== undefined && temp !== null) ? Number(temp) : 50;
        return Math.round(6500 - (t / 100) * (6500 - 2500));
    }

    function apply(monName, enabled, temp, autoMode) {
        if (!monName || !Caching.serpantinumDir) return;

        if (enabled) {
            let kelvin = kelvinFromTemp(temp);
            let modeStr = autoMode ? "auto" : "manual";
            let coords = getCoordinates();

            Quickshell.execDetached([
                "bash",
                Caching.serpantinumDir + "/scripts/blue_light_filter.sh",
                "set",
                kelvin.toString(),
                monName,
                modeStr,
                coords.lat.toString(),
                coords.lon.toString()
            ]);
        } else {
            Quickshell.execDetached([
                "bash",
                Caching.serpantinumDir + "/scripts/blue_light_filter.sh",
                "reset",
                monName
            ]);
        }
    }

    function applyForMonitor(monName) {
        if (!monName) return;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        let mSet = (ds && ds.monitors && ds.monitors[monName]) ? ds.monitors[monName] : {};
        let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
        let isAu = mSet.auto !== undefined ? mSet.auto : false;
        let temp = mSet.temperature !== undefined ? mSet.temperature : 50;

        apply(monName, isEn, temp, isAu);
    }

    function setEnabled(monName, enabled) {
        updateMonitorSetting(monName, "enabled", enabled);
    }

    function setAuto(monName, autoMode) {
        updateMonitorSetting(monName, "auto", autoMode);
    }

    function setTemperature(monName, temp) {
        updateMonitorSetting(monName, "temperature", temp);
    }

    function reset(monName) {
        if (!monName || !Caching.serpantinumDir) return;

        Quickshell.execDetached([
            "bash",
            Caching.serpantinumDir + "/scripts/blue_light_filter.sh",
            "reset",
            monName
        ]);
    }

    function updateMonitorSetting(monName, key, value) {
        if (!monName) return;

        let current = Config.getSetting("display", defaultDisplaySettings);
        if (!current.monitors) current.monitors = {};
        if (!current.monitors[monName]) current.monitors[monName] = {};

        current.monitors[monName][key] = value;
        Config.setSetting("display", current);

        let mSet = current.monitors[monName];
        let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
        let isAu = mSet.auto !== undefined ? mSet.auto : false;
        let temp = mSet.temperature !== undefined ? mSet.temperature : 50;

        apply(monName, isEn, temp, isAu);
    }

    function applyAll() {
        let ds = Config.getSetting("display", defaultDisplaySettings);
        if (!ds || !ds.monitors) return;

        let keys = Object.keys(ds.monitors);
        for (let i = 0; i < keys.length; i++) {
            let mName = keys[i];
            let mSet = ds.monitors[mName];
            if (mSet) {
                let isEn = mSet.enabled !== undefined ? mSet.enabled : false;
                let isAu = mSet.auto !== undefined ? mSet.auto : false;
                let temp = mSet.temperature !== undefined ? mSet.temperature : 50;
                apply(mName, isEn, temp, isAu);
            }
        }
    }

    Process {
        id: outputDetector
        running: false
        command: [
            "bash",
            "-c",
            root.compositor === "niri"
                ? "niri msg -j outputs 2>/dev/null"
                : (root.compositor === "sway"
                    ? "swaymsg -t get_outputs -r 2>/dev/null"
                    : "hyprctl monitors all -j 2>/dev/null || hyprctl monitors -j 2>/dev/null")
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                root.applyAll();
            }
        }
    }

    function reload() {
        outputDetector.running = false;
        outputDetector.running = true;
    }

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onSettingsLoaded() {
            root.applyAll();
        }
    }

    Connections {
        target: typeof Location !== "undefined" ? Location : null
        function onLocationUpdated() {
            root.applyAll();
        }
    }

    Component.onCompleted: {
        root.applyAll();
    }
}
