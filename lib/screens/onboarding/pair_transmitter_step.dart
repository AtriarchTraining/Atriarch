import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/atriarch_theme.dart';
import 'onboarding_flow.dart';

/// Step 2 of the first-run wizard (Gate 2 #19, addendum §7.10).
///
/// Runs a Bluetooth scan and lets the user tap a discovered transmitter to
/// pair. Success = `bleService.isConnected` after connect(). The BLE layer
/// persists the peripheral UUID into `device_pairing` on its own. On success
/// we auto-advance to step 3 after 1.5s.
///
/// A `scanRunner`/`connectRunner` override pair is the test seam — widget
/// tests inject fakes rather than drive `FlutterBluePlus.startScan` directly
/// (no real adapter in CI). Production leaves both null and falls through to
/// the real [FlutterBluePlus] + [AppState.bleService.connect] paths.
class PairTransmitterStep extends StatefulWidget {
  final VoidCallback onPaired;

  /// Optional test override. Pumps scan lifecycle manually — when non-null
  /// we DO NOT call `FlutterBluePlus.startScan` and we read scan results
  /// from the supplied [scanResultsStream] instead.
  final Stream<List<ScanResult>>? scanResultsStream;

  /// When non-null and the user taps a device, we call this instead of
  /// `AppState.bleService.connect`. Returns true on success.
  final Future<bool> Function(BluetoothDevice device)? connectOverride;

  /// Fires the scan. Defaults to `FlutterBluePlus.startScan`.
  final Future<void> Function()? scanStarter;

  const PairTransmitterStep({
    super.key,
    required this.onPaired,
    this.scanResultsStream,
    this.connectOverride,
    this.scanStarter,
  });

  @override
  State<PairTransmitterStep> createState() => _PairTransmitterStepState();
}

class _PairTransmitterStepState extends State<PairTransmitterStep> {
  int _failureCount = 0;
  bool _paired = false;
  bool _connecting = false;
  Timer? _advanceTimer;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    try {
      final starter = widget.scanStarter ??
          () => FlutterBluePlus.startScan(
                timeout: const Duration(seconds: 4),
              );
      await starter();
    } catch (_) {
      // Scan errors surface through the failure count / Retry path below.
    }
  }

  Future<void> _onRetry() async {
    setState(() {});
    await _startScan();
  }

  Future<void> _onTapDevice(BluetoothDevice device) async {
    if (_connecting || _paired) return;
    setState(() => _connecting = true);

    final state = context.read<AppState>();
    bool ok;
    try {
      if (widget.connectOverride != null) {
        ok = await widget.connectOverride!(device);
      } else {
        await state.bleService.connect(device);
        ok = state.bleService.isConnected;
      }
    } catch (_) {
      ok = false;
    }

    if (!mounted) return;
    if (ok) {
      setState(() {
        _paired = true;
        _connecting = false;
      });
      _advanceTimer?.cancel();
      _advanceTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        widget.onPaired();
      });
    } else {
      setState(() {
        _connecting = false;
        _failureCount += 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return Padding(
      padding: const EdgeInsets.all(AtriarchSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OnboardingStepIndicator(currentStep: 2),
          const SizedBox(height: AtriarchSpacing.xl),
          Text(
            'Pair your transmitter',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          Text(
            'Tap your Atriarch transmitter when it appears below.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
          ),
          const SizedBox(height: AtriarchSpacing.lg),
          Expanded(
            child: _paired
                ? _PairedBanner(tokens: tokens)
                : _DeviceList(
                    stream: widget.scanResultsStream ??
                        FlutterBluePlus.scanResults,
                    onTap: _connecting ? null : _onTapDevice,
                    connecting: _connecting,
                  ),
          ),
          if (!_paired && _failureCount >= 1) ...[
            _HelpCard(tokens: tokens),
            const SizedBox(height: AtriarchSpacing.md),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
          const SizedBox(height: AtriarchSpacing.md),
        ],
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  final Stream<List<ScanResult>> stream;
  final Future<void> Function(BluetoothDevice)? onTap;
  final bool connecting;

  const _DeviceList({
    required this.stream,
    required this.onTap,
    required this.connecting,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.atriarch;
    return StreamBuilder<List<ScanResult>>(
      stream: stream,
      initialData: const <ScanResult>[],
      builder: (context, snapshot) {
        final results = snapshot.data ?? const <ScanResult>[];
        if (results.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: AtriarchSpacing.md),
                Text(
                  'Scanning for devices…',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: tokens.border),
          itemBuilder: (context, i) {
            final r = results[i];
            final name = r.device.platformName.isNotEmpty
                ? r.device.platformName
                : r.device.remoteId.toString();
            final connectable = r.advertisementData.connectable;
            return ListTile(
              title: Text(name),
              subtitle: Text(r.device.remoteId.toString()),
              trailing: connecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('${r.rssi} dBm'),
              enabled: connectable && onTap != null,
              onTap: (connectable && onTap != null)
                  ? () => onTap!(r.device)
                  : null,
            );
          },
        );
      },
    );
  }
}

class _PairedBanner extends StatelessWidget {
  final AtriarchTokens tokens;

  const _PairedBanner({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: tokens.statusLive, size: 64),
          const SizedBox(height: AtriarchSpacing.md),
          Text(
            'Transmitter paired',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: tokens.statusLive,
                ),
          ),
          const SizedBox(height: AtriarchSpacing.sm),
          Text(
            'Continuing…',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  final AtriarchTokens tokens;

  const _HelpCard({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AtriarchSpacing.md),
      decoration: BoxDecoration(
        color: tokens.bgElevated,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(AtriarchRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.help_outline, color: tokens.statusArmed),
          const SizedBox(width: AtriarchSpacing.md),
          Expanded(
            child: Text(
              'Check transmitter is powered on (LED solid) and within '
              'Bluetooth range (under 30 ft). Toggle Bluetooth off/on if '
              'this fails twice.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
