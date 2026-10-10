// Latency harness (Task 25, NFR-1, G1a, G1b, G2, G3). Automated measurement of
// the four latency budgets against fakes with injectable clocks, asserting the
// budgets using simulated timings. Real-device numbers on the reference hardware
// (Pixel 7, iPhone 12) under reference network conditions are a device-only step
// and are deferred to the developer's machine and CI on reference devices; this
// harness proves the measurement methodology and the budget assertions headless.
//
// Budgets (requirements §1):
//   G1a <= 1.5 s : webhook receipt at backend -> push delivered to device.
//   G1b <= 2.0 s : resident taps Open -> first caption glyph rendered (Clarity).
//   G2  <= 1.0 s : caption partial-result latency after speech onset (Clarity).
//   G3  <= 2.0 s : reply audible at the door after tap (tap -> audio start).
//
// Each budget is measured as a span between two injected instants, so a test can
// feed simulated timings and the harness reports pass/fail against the budget.

import 'package:flutter/foundation.dart';

/// The four latency goals (requirements §1, NFR-1).
enum LatencyGoal { g1a, g1b, g2, g3 }

/// The budget ceiling for each goal, in milliseconds.
const Map<LatencyGoal, int> kLatencyBudgetsMs = <LatencyGoal, int>{
  LatencyGoal.g1a: 1500,
  LatencyGoal.g1b: 2000,
  LatencyGoal.g2: 1000,
  LatencyGoal.g3: 2000,
};

/// A dash-free human name for each goal (NFR-10), for reports.
String latencyGoalName(LatencyGoal goal) {
  switch (goal) {
    case LatencyGoal.g1a:
      return 'G1a webhook to push';
    case LatencyGoal.g1b:
      return 'G1b open to first caption';
    case LatencyGoal.g2:
      return 'G2 speech to partial caption';
    case LatencyGoal.g3:
      return 'G3 tap to reply audible';
  }
}

/// A single measurement of a goal.
@immutable
class LatencyMeasurement {
  const LatencyMeasurement(
      {required this.goal, required this.startMs, required this.endMs});

  final LatencyGoal goal;
  final int startMs;
  final int endMs;

  int get elapsedMs => endMs - startMs;
  int get budgetMs => kLatencyBudgetsMs[goal]!;

  /// Within budget when the elapsed time does not exceed the ceiling (NFR-1).
  bool get withinBudget => elapsedMs <= budgetMs;
}

/// Records latency measurements against injected clocks and asserts budgets. A
/// test starts a goal at a simulated instant and stops it at a later instant.
class LatencyHarness {
  final Map<LatencyGoal, int> _startedAt = <LatencyGoal, int>{};
  final List<LatencyMeasurement> _measurements = <LatencyMeasurement>[];

  List<LatencyMeasurement> get measurements => List.unmodifiable(_measurements);

  /// Mark the start instant (ms) of a goal.
  void start(LatencyGoal goal, int atMs) {
    _startedAt[goal] = atMs;
  }

  /// Mark the end instant (ms) of a goal and record the measurement. Throws if
  /// the goal was not started (a measurement must have both ends).
  LatencyMeasurement stop(LatencyGoal goal, int atMs) {
    final start = _startedAt.remove(goal);
    if (start == null) {
      throw StateError('Latency goal ${latencyGoalName(goal)} was not started');
    }
    final m = LatencyMeasurement(goal: goal, startMs: start, endMs: atMs);
    _measurements.add(m);
    return m;
  }

  /// The latest measurement for a goal, or null if none recorded.
  LatencyMeasurement? latest(LatencyGoal goal) {
    for (var i = _measurements.length - 1; i >= 0; i--) {
      if (_measurements[i].goal == goal) return _measurements[i];
    }
    return null;
  }

  /// True when every recorded measurement is within its budget (NFR-1). Used as
  /// the CI regression gate on the reference devices.
  bool get allWithinBudget => _measurements.every((m) => m.withinBudget);

  /// The goals that exceeded budget (empty when all pass). For a failure report.
  List<LatencyGoal> get regressions =>
      _measurements.where((m) => !m.withinBudget).map((m) => m.goal).toList();
}
