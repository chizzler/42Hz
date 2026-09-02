/*
 * 42Hz — the diagnostics report.
 *
 * What `42hz --diagnostics` prints: the five capabilities the window reports
 * in words, answered from a terminal instead, plus the two versions and what
 * 42Hz can see of the graph.
 *
 * The hard constraint is that this MUST NOT build a processing graph.
 * pw::Manager's constructor loads 42Hz's virtual devices and then spins until
 * they appear, so constructing it would make the diagnostic change the very
 * routing it is being asked about -- and would abort outright, through
 * util::fatal, in the one case the report exists to explain. So this opens its
 * own read-only PipeWire connection: a context, a registry, one roundtrip, and
 * nothing bound that could move a stream.
 *
 * It hard-codes no identity. Every name 42Hz answers to comes from the table
 * in spike/reduce-deps.py, so the patched main.cpp hands them in and this file
 * only formats them.
 */

#pragma once

#include <QString>

namespace hz {

// The facts the core already holds, handed in rather than restated here.
struct Identity {
  QString version;          // 42Hz's own, PROJECT_VERSION in the patched tree
  QString upstreamVersion;  // the Easy Effects release the core derives from
  QString applicationId;
  QString sinkName;         // the virtual sink streams are moved to
  QString sourceName;
  QString nodePrefix;       // 42Hz's own DSP filter nodes
  QString equalizerUri;     // the LV2 plugin the equalizer needs
  bool instanceRunning;     // another instance holds the single-instance lock
};

// Prints the report to stdout and returns the process exit status: 0 when
// everything this machine is responsible for is in place, 1 otherwise. A
// diagnostic that always succeeds is not one a script can branch on. 42Hz not
// running is not a failure; an unreachable audio service, a missing LV2
// provider, unreadable theme state, and a running instance with no nodes in
// the graph all are.
auto report(const Identity& identity) -> int;

}  // namespace hz
