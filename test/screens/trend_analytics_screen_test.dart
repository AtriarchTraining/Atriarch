// test/screens/trend_analytics_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:atriarch/screens/trend_analytics_screen.dart';
import 'package:atriarch/state/app_state.dart';
import 'package:atriarch/theme/atriarch_theme.dart';
import 'package:atriarch/repositories/metrics_repository.dart';

class _FakeMetricsRepo implements MetricsRepository {
  final List<MetricSnapshot> _data;
  _FakeMetricsRepo(this._data);

  @override
  Future<List<MetricSnapshot>> listRecentMetrics({int limit = 20}) async =>
      _data.take(limit).toList();

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError(i.memberName.toString());
}

Widget _buildApp(AppState state) => ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: buildAtriarchDarkTheme(),
        home: const TrendAnalyticsScreen(),
      ),
    );

MetricSnapshot _snap({
  String id = 'sid',
  int? draw = 450,
  int? reaction = 350,
  int? split = 150,
  int? transition = 200,
}) => MetricSnapshot(
      sessionId: id,
      drawMs: draw,
      avgReactionMs: reaction,
      avgSplitMs: split,
      avgTransitionMs: transition,
    );

void main() {
  testWidgets('shows empty state when metricsRepo is null', (tester) async {
    await tester.pumpWidget(_buildApp(AppState()));
    await tester.pump();
    expect(find.text('NO SESSIONS RECORDED YET.'), findsOneWidget);
  });

  testWidgets('shows empty state when repo returns no snapshots', (tester) async {
    final state = AppState(metricsRepo: _FakeMetricsRepo([]));
    await tester.pumpWidget(_buildApp(state));
    await tester.pump();
    expect(find.text('NO SESSIONS RECORDED YET.'), findsOneWidget);
  });

  testWidgets('renders four metric panels when data is present', (tester) async {
    final snapshots = List.generate(5, (i) => _snap(id: 'sid-$i', draw: 450 - i * 10));
    final state = AppState(metricsRepo: _FakeMetricsRepo(snapshots));
    await tester.pumpWidget(_buildApp(state));
    await tester.pump();
    expect(find.text('DRAW'), findsOneWidget);
    expect(find.text('AVG REACTION'), findsOneWidget);
    expect(find.text('AVG SPLIT'), findsOneWidget);
    expect(find.text('AVG TRANSITION'), findsOneWidget);
  });

  testWidgets('panels show NO DATA when all snapshots have null metrics', (tester) async {
    final snapshots = [_snap(id: 'sid-0', draw: null, reaction: null, split: null, transition: null)];
    final state = AppState(metricsRepo: _FakeMetricsRepo(snapshots));
    await tester.pumpWidget(_buildApp(state));
    await tester.pump();
    expect(find.text('NO DATA'), findsNWidgets(4));
  });

  testWidgets('screen title is TREND_ANALYTICS', (tester) async {
    final state = AppState(metricsRepo: _FakeMetricsRepo([]));
    await tester.pumpWidget(_buildApp(state));
    await tester.pump();
    expect(find.text('TREND_ANALYTICS'), findsOneWidget);
  });
}
