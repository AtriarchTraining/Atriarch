import 'package:flutter/material.dart';

/// Recent drills screen — Phase-3 TODO stub.
///
/// Gate-2 shipped a session-scoped list driven by the now-deleted Hive
/// `SessionSummary` + `DrillLogRepository`. Stage-3 replaces those with the
/// SQLite `sessions` table accessed through [RangeSessionView]. The real
/// tactical rewrite lands in Phase 3.
///
/// For Phase-2 exit the tree must compile — this stub keeps the public type
/// `RecentDrillsScreen` importable for `home_screen.dart`'s route.
class RecentDrillsScreen extends StatelessWidget {
  const RecentDrillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recent Drills')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Recent drills — Phase 3 TODO.\n\n'
            'Reads from SQLite sessions table via RangeSessionView.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
