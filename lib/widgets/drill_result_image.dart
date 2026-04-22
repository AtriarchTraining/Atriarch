import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/session_event.dart';
import '../theme/atriarch_theme.dart';
import '../util/results_view_model.dart';

/// Shareable drill-result composition (addendum §4.D). Always rendered
/// against [buildAtriarchDarkTheme] regardless of the active app theme so
/// the image stays on-brand on both indoor and outdoor devices.
///
/// Sized 1080x1920 logical pixels for story / wallpaper-friendly output.
/// Use [ScreenshotController.captureFromWidget] with this widget to get a
/// PNG byte array without mounting it in the widget tree.
class DrillResultImage extends StatelessWidget {
  static const double width = 1080;
  static const double height = 1920;

  final ResultsViewModel model;

  const DrillResultImage({super.key, required this.model});

  @override
  Widget build(BuildContext context) {
    // Force dark theme + the target pixel size. We wrap in a MediaQuery so
    // inherited font scale from the captured host context doesn't rescale
    // the composition.
    return MediaQuery(
      data: const MediaQueryData(size: Size(width, height)),
      child: Theme(
        data: buildAtriarchDarkTheme(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (themedContext) {
              final tokens = themedContext.atriarch;
              return Material(
                color: tokens.bgBase,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: _buildBody(themedContext, tokens),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AtriarchTokens tokens) {
    final events = model.events;
    final completions = events
        .where((e) => e.type == EventType.targetComplete)
        .toList(growable: false);
    final activations = events
        .where((e) => e.type == EventType.targetActivated)
        .toList(growable: false);
    final violations = events
        .where((e) => e.type == EventType.noShootViolation)
        .length;
    final lateHits =
        events.where((e) => e.type == EventType.lateHit).length;
    final hits =
        events.where((e) => e.type == EventType.hitDetected).toList();

    // Expected completion count == total activations (we treat every
    // activation as an opportunity to complete). This mirrors the live
    // results breakdown so "12 of 15" feels the same post-drill as in-app.
    final expected = activations.length;

    final perTarget = <int, _PerTargetRow>{};
    for (final id in activations.map((e) => e.targetId).whereType<int>()) {
      final done = completions.where((e) => e.targetId == id).toList();
      final hitsForTarget = hits.where((e) => e.targetId == id).length;
      final avg = done.isEmpty
          ? 0
          : (done.map((e) => e.totalTimeMs ?? 0).reduce((a, b) => a + b) /
                  done.length)
              .round();
      perTarget[id] = _PerTargetRow(
        label: model.nameResolver.display(id),
        avgMs: avg,
        hits: hitsForTarget,
      );
    }

    final perTargetEntries = perTarget.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final dateLabel = _formatDate(model.startedAt);
    final durationLabel = _formatDuration(model.duration);

    return Padding(
      padding: const EdgeInsets.fromLTRB(88, 120, 88, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ATRIARCH',
            style: GoogleFonts.interTight(
              fontSize: 72,
              fontWeight: FontWeight.w700,
              letterSpacing: 6,
              color: tokens.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${model.presetName} · $durationLabel',
            style: GoogleFonts.interTight(
              fontSize: 40,
              fontWeight: FontWeight.w500,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            dateLabel,
            style: GoogleFonts.interTight(
              fontSize: 32,
              fontWeight: FontWeight.w400,
              color: tokens.textTertiary,
            ),
          ),
          const Spacer(),
          Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '${completions.length} of $expected',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 220,
                    fontWeight: FontWeight.w300,
                    height: 1.0,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'completions',
                  style: GoogleFonts.interTight(
                    fontSize: 44,
                    fontWeight: FontWeight.w500,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          Center(
            child: Text(
              '· $violations violations · $lateHits late hits ·',
              style: GoogleFonts.interTight(
                fontSize: 36,
                fontWeight: FontWeight.w400,
                color: tokens.textTertiary,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Per-target',
            style: GoogleFonts.interTight(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          ...perTargetEntries.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 280,
                    child: Text(
                      e.value.label,
                      style: GoogleFonts.interTight(
                        fontSize: 36,
                        fontWeight: FontWeight.w500,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${e.value.avgMs}ms avg · ${e.value.hits} hits',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 32,
                        fontWeight: FontWeight.w400,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }
}

class _PerTargetRow {
  final String label;
  final int avgMs;
  final int hits;

  const _PerTargetRow({
    required this.label,
    required this.avgMs,
    required this.hits,
  });
}
