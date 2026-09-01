pragma Singleton

import QtQuick

// The shipped audio profiles: named EQ curves, read-only, selected in the
// editor.
//
// These are creative control, not correction. Omarchy ships speaker tunings
// fitted by measurement for particular hardware, and that is a different job
// done somewhere else -- a profile here changes how something sounds because
// someone wanted it to, and must never read as a fix for a device. Hence names
// that say what each one does, and no genres.
//
// A profile is a *curve*, not a list of gains. Each is a handful of anchor
// points, and the gain for a band is interpolated from them at that band's
// actual centre frequency. Ten stored numbers would be welded to numBands = 10:
// change the band count and every curve would land on the wrong frequencies
// with nothing failing to say so.
//
// A singleton rather than files. The core's PresetsManager would load these,
// but its presets are whole-pipeline JSON in the user's config directory and
// loading one sets the plugins list -- which fights the rule that 42Hz's chain
// is exactly equalizer#0 -- and it brings add, rename, import, export,
// community presets and per-device autoload, none of which is in this release.
// A table has no file, no install step and nothing to manage.
QtObject {
    id: profiles

    // Anchors are { hz, db }, in ascending frequency. Between two anchors the
    // gain is linear in log-frequency and linear in dB: dB is already a
    // logarithmic quantity, so a straight line between two anchors is the
    // straight line a reader sees on the curve.
    //
    // Outside the outermost anchors the end value is held rather than
    // extrapolated. That is what makes `bass`, whose last anchor is at 500 Hz,
    // a shelf that stops rather than a slope that keeps falling to nothing.
    //
    // Every anchor stays inside the editor's own +/-12 dB travel. A profile
    // that asked for more would draw pinned to a rail with no way to see how
    // far past it the setting actually went, which is the dishonest case the
    // whole spectrum design is built to avoid.
    //
    // `note` is what the profile does, in the fewest words that say it. The
    // editor draws it beside the curve, so the set explains itself rather than
    // being a row of words you learn by trying each one.
    //
    // `group` splits the row into runs of related intent. Nine names in an
    // undifferentiated line is a list to be read; four short runs is a thing to
    // be scanned, and the grouping is the same one the table is written in.
    readonly property var list: [
        {
            "name": "flat",
            "note": "the zero curve",
            "group": 0,
            "anchors": [
                { "hz": 20, "db": 0 },
                { "hz": 20000, "db": 0 }
            ]
        },
        {
            // Quiet listening. The ear loses sensitivity at both extremes as
            // level falls -- the equal-loudness contours -- so a quiet mix
            // reads as thin and dull rather than merely quieter. This puts
            // that back: strong at the bottom, untouched through the mids
            // where the contours are flattest, gentle at the top.
            "name": "loudness",
            "note": "for listening quietly",
            "group": 1,
            "anchors": [
                { "hz": 20, "db": 7.5 },
                { "hz": 60, "db": 6 },
                { "hz": 150, "db": 3 },
                { "hz": 400, "db": 0.5 },
                { "hz": 1500, "db": 0 },
                { "hz": 5000, "db": 0.5 },
                { "hz": 10000, "db": 2.5 },
                { "hz": 20000, "db": 4 }
            ]
        },
        {
            // The other quiet curve, and the mirror of `loudness`. Low
            // frequencies are the ones that pass through a wall, so this takes
            // them out rather than putting them back, and lifts 1-3 kHz so
            // that detail and speech survive at a level that disturbs nobody.
            // Late listening, shared walls, a sleeping house.
            "name": "night",
            "note": "quiet, and it stays in the room",
            "group": 1,
            "anchors": [
                { "hz": 20, "db": -11 },
                { "hz": 50, "db": -10 },
                { "hz": 100, "db": -6.5 },
                { "hz": 200, "db": -3 },
                { "hz": 400, "db": -0.5 },
                { "hz": 1000, "db": 1.5 },
                { "hz": 2500, "db": 3 },
                { "hz": 5000, "db": 2 },
                { "hz": 10000, "db": 0 },
                { "hz": 20000, "db": -1 }
            ]
        },
        {
            // A low shelf, and only that. It stops by 500 Hz rather than
            // tilting the whole curve, so it adds weight without taking the
            // mids down with it.
            "name": "bass",
            "note": "a low shelf",
            "group": 2,
            "anchors": [
                { "hz": 20, "db": 7 },
                { "hz": 60, "db": 6.5 },
                { "hz": 120, "db": 5 },
                { "hz": 250, "db": 2 },
                { "hz": 500, "db": 0 },
                { "hz": 20000, "db": 0 }
            ]
        },
        {
            // Games and electronic music. Not a bigger `bass`: it lifts the
            // kick region and the 3 kHz attack region and takes out the
            // 300-500 Hz box between them, so transients arrive rather than
            // the whole bottom end getting heavier.
            "name": "punch",
            "note": "kick and attack, box out",
            "group": 2,
            "anchors": [
                { "hz": 20, "db": 2 },
                { "hz": 50, "db": 5 },
                { "hz": 90, "db": 4.5 },
                { "hz": 180, "db": 1 },
                { "hz": 350, "db": -2.5 },
                { "hz": 700, "db": -2 },
                { "hz": 1500, "db": 0 },
                { "hz": 3000, "db": 3 },
                { "hz": 5000, "db": 2.5 },
                { "hz": 10000, "db": 1 },
                { "hz": 20000, "db": 0.5 }
            ]
        },
        {
            // A tilt rather than a shelf at either end: body up, top down,
            // crossing zero around 1 kHz. What `bass` and `soft` would do
            // together, done as one gradient so the middle does not develop a
            // step where the two would have met.
            "name": "warm",
            "note": "body up, top down",
            "group": 2,
            "anchors": [
                { "hz": 20, "db": 1 },
                { "hz": 60, "db": 2 },
                { "hz": 150, "db": 3.5 },
                { "hz": 300, "db": 3 },
                { "hz": 600, "db": 1.5 },
                { "hz": 1200, "db": 0 },
                { "hz": 3000, "db": -1 },
                { "hz": 8000, "db": -2.5 },
                { "hz": 20000, "db": -3.5 }
            ]
        },
        {
            // Voice. Rumble and room noise below ~100 Hz carry nothing a
            // speaking voice needs, the 200-400 Hz region is where a close mic
            // gets muddy, and 1-4 kHz is where consonants live.
            "name": "speech",
            "note": "voices and podcasts",
            "group": 3,
            "anchors": [
                { "hz": 20, "db": -8 },
                { "hz": 60, "db": -6 },
                { "hz": 120, "db": -2.5 },
                { "hz": 250, "db": -1.5 },
                { "hz": 600, "db": 0 },
                { "hz": 1500, "db": 2.5 },
                { "hz": 3000, "db": 4 },
                { "hz": 5000, "db": 2.5 },
                { "hz": 9000, "db": 0 },
                { "hz": 20000, "db": -1 }
            ]
        },
        {
            // The counterpart to `soft`, and deliberately smaller than it. A
            // lift is more tiring than a cut of the same size, so where `soft`
            // takes 7 dB off the top this puts 5 back, from a little higher up.
            "name": "air",
            "note": "opens the top",
            "group": 3,
            "anchors": [
                { "hz": 20, "db": 0 },
                { "hz": 2000, "db": 0 },
                { "hz": 4000, "db": 1 },
                { "hz": 8000, "db": 3 },
                { "hz": 14000, "db": 4.5 },
                { "hz": 20000, "db": 5 }
            ]
        },
        {
            // Harsh sources, and long sessions. A progressive cut from a few
            // kHz up rather than a shelf, so it takes the edge off without
            // sounding like a blanket over the speaker.
            "name": "soft",
            "note": "takes the edge off",
            "group": 3,
            "anchors": [
                { "hz": 20, "db": 0 },
                { "hz": 1000, "db": 0 },
                { "hz": 2500, "db": -1 },
                { "hz": 5000, "db": -3 },
                { "hz": 10000, "db": -5.5 },
                { "hz": 20000, "db": -7 }
            ]
        }
    ]

    readonly property int flatIndex: 0

    function nameAt(index) {
        return index >= 0 && index < profiles.list.length ? profiles.list[index].name : "";
    }

    // What the profile does, for the editor to draw beside the curve.
    function noteAt(index) {
        return index >= 0 && index < profiles.list.length ? profiles.list[index].note : "";
    }

    // The gain a profile asks for at one frequency.
    function gainAt(index, hz) {
        if (index < 0 || index >= profiles.list.length)
            return 0;

        const a = profiles.list[index].anchors;

        if (a.length === 0)
            return 0;

        if (hz <= a[0].hz)
            return a[0].db;

        for (let i = 1; i < a.length; i++) {
            if (hz > a[i].hz)
                continue;

            const lo = a[i - 1];
            const hi = a[i];

            // Guard a degenerate pair rather than dividing by zero and
            // handing back a NaN that would reach a band gain.
            const span = Math.log(hi.hz) - Math.log(lo.hz);
            if (span <= 0)
                return hi.db;

            const t = (Math.log(hz) - Math.log(lo.hz)) / span;
            return lo.db + t * (hi.db - lo.db);
        }

        return a[a.length - 1].db;
    }

    // The whole curve, resolved against the frequencies a band layout actually
    // has. The caller supplies them, because only the core knows where
    // calculateFrequencies() put the bands.
    function curveFor(index, frequencies) {
        const out = [];

        for (let i = 0; i < frequencies.length; i++)
            out.push(Math.round(profiles.gainAt(index, frequencies[i]) * 10) / 10);

        return out;
    }

    // Which profile a set of gains is, if it is any of them.
    //
    // Called on load so that a curve restored from settings is still named
    // rather than reading as someone's custom edit. The tolerance is half the
    // step the editor writes in, so a curve that was applied and left alone
    // matches and one that was nudged does not.
    function match(gains, frequencies) {
        for (let p = 0; p < profiles.list.length; p++) {
            const curve = profiles.curveFor(p, frequencies);

            let same = curve.length === gains.length;
            for (let i = 0; same && i < curve.length; i++)
                same = Math.abs(curve[i] - gains[i]) < 0.5;

            if (same)
                return p;
        }

        return -1;
    }
}
