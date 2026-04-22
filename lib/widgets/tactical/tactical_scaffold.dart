import 'package:flutter/material.dart';
import 'tactical_app_bar.dart';
import 'tactical_grid_background.dart';

class TacticalScaffold extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool extendBodyBehindAppBar;

  const TacticalScaffold({
    super.key,
    this.title,
    this.trailing,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.extendBodyBehindAppBar = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: title != null
          ? TacticalAppBar(title: title!, trailing: trailing)
          : null,
      body: TacticalGridBackground(child: body),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
    );
  }
}
