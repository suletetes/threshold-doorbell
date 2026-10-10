import 'package:flutter_test/flutter_test.dart';
import 'package:threshold/perf/latency_harness.dart';

void main() {
  group('Latency harness (Task 25, NFR-1, G1a, G1b, G2, G3)', () {
    test('budgets match the requirements (NFR-1)', () {
      expect(kLatencyBudgetsMs[LatencyGoal.g1a], 1500);
      expect(kLatencyBudgetsMs[LatencyGoal.g1b], 2000);
      expect(kLatencyBudgetsMs[LatencyGoal.g2], 1000);
      expect(kLatencyBudgetsMs[LatencyGoal.g3], 2000);
    });

    test('G1a within 1.5 s passes (webhook to push)', () {
      final h = LatencyHarness();
      h.start(LatencyGoal.g1a, 0);
      final m = h.stop(LatencyGoal.g1a, 1200); // 1.2 s
      expect(m.elapsedMs, 1200);
      expect(m.withinBudget, isTrue);
    });

    test('G1a over 1.5 s is a regression', () {
      final h = LatencyHarness();
      h.start(LatencyGoal.g1a, 0);
      final m = h.stop(LatencyGoal.g1a, 1600); // 1.6 s
      expect(m.withinBudget, isFalse);
      expect(h.regressions, contains(LatencyGoal.g1a));
    });

    test('G1b within 2.0 s passes (open to first caption)', () {
      final h = LatencyHarness();
      h.start(LatencyGoal.g1b, 100);
      final m = h.stop(LatencyGoal.g1b, 100 + 1800);
      expect(m.withinBudget, isTrue);
    });

    test('G2 within 1.0 s passes (speech to partial caption)', () {
      final h = LatencyHarness();
      h.start(LatencyGoal.g2, 0);
      final m = h.stop(LatencyGoal.g2, 900);
      expect(m.withinBudget, isTrue);
    });

    test('G2 at exactly 1.0 s is within budget (inclusive ceiling)', () {
      final h = LatencyHarness();
      h.start(LatencyGoal.g2, 0);
      final m = h.stop(LatencyGoal.g2, 1000);
      expect(m.withinBudget, isTrue);
    });

    test('G3 within 2.0 s passes (tap to reply audible)', () {
      final h = LatencyHarness();
      h.start(LatencyGoal.g3, 500);
      final m = h.stop(LatencyGoal.g3, 500 + 1900);
      expect(m.withinBudget, isTrue);
    });

    test('a full run of all four goals within budget reports allWithinBudget',
        () {
      final h = LatencyHarness();
      h.start(LatencyGoal.g1a, 0);
      h.stop(LatencyGoal.g1a, 1400);
      h.start(LatencyGoal.g1b, 0);
      h.stop(LatencyGoal.g1b, 1900);
      h.start(LatencyGoal.g2, 0);
      h.stop(LatencyGoal.g2, 800);
      h.start(LatencyGoal.g3, 0);
      h.stop(LatencyGoal.g3, 1800);
      expect(h.allWithinBudget, isTrue);
      expect(h.regressions, isEmpty);
    });

    test('one regression among passes is flagged', () {
      final h = LatencyHarness();
      h.start(LatencyGoal.g1a, 0);
      h.stop(LatencyGoal.g1a, 1400);
      h.start(LatencyGoal.g3, 0);
      h.stop(LatencyGoal.g3, 2500); // over
      expect(h.allWithinBudget, isFalse);
      expect(h.regressions, <LatencyGoal>[LatencyGoal.g3]);
    });

    test('stopping an unstarted goal throws', () {
      final h = LatencyHarness();
      expect(() => h.stop(LatencyGoal.g1a, 100), throwsStateError);
    });

    test('latest returns the most recent measurement for a goal', () {
      final h = LatencyHarness();
      h.start(LatencyGoal.g2, 0);
      h.stop(LatencyGoal.g2, 500);
      h.start(LatencyGoal.g2, 1000);
      h.stop(LatencyGoal.g2, 1700);
      expect(h.latest(LatencyGoal.g2)!.elapsedMs, 700);
    });

    test('goal names are dash-free (NFR-10)', () {
      for (final g in LatencyGoal.values) {
        expect(latencyGoalName(g).contains('\u2014'), isFalse);
        expect(latencyGoalName(g).contains('\u2013'), isFalse);
      }
    });
  });
}
