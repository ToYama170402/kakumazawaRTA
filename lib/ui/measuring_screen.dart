import 'dart:async';

import 'package:flutter/material.dart';

import '../measurement/location_provider.dart';
import '../measurement/measurement_controller.dart';
import '../measurement/position.dart';
import '../measurement/position_sampler.dart';
import '../routes/route_definition.dart';
import 'name_entry_screen.dart';

enum MeasuringPhase { waitingStart, measuring, finished }

/// 計測中画面（Issue #46）。
///
/// 開始ボタンで武装し、start_bounds 入域で自動開始、goal_bounds 到達で
/// 自動停止する（判定は [MeasurementController]）。停止後はネーム入力へ進み、
/// 確定したら [onFinished] に履歴とニックネームを渡す。
class MeasuringScreen extends StatefulWidget {
  const MeasuringScreen({
    super.key,
    required this.route,
    required this.locationProvider,
    required this.organizationDisplayName,
    this.onFinished,
  });

  final RouteDefinition route;
  final LocationProvider locationProvider;
  final String organizationDisplayName;
  final Future<void> Function(List<GeoPoint> history, String nickname)?
  onFinished;

  @override
  State<MeasuringScreen> createState() => _MeasuringScreenState();
}

class _MeasuringScreenState extends State<MeasuringScreen> {
  late final MeasurementController _controller;
  late final PositionSampler _sampler;
  StreamSubscription<MeasurementEvent>? _eventSubscription;
  StreamSubscription<GeoPoint>? _positionSubscription;
  Timer? _ticker;

  MeasuringPhase _phase = MeasuringPhase.waitingStart;
  bool _armed = false;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _controller = MeasurementController(
      startBounds: widget.route.startBounds,
      goalBounds: widget.route.goalBounds,
    );
    _sampler = PositionSampler(provider: widget.locationProvider);
    _positionSubscription = _sampler.stream.listen(_controller.onLocation);
    _eventSubscription = _controller.events.listen(_handleEvent);
  }

  void _handleEvent(MeasurementEvent event) {
    if (!mounted) {
      return;
    }
    if (event.type == 'started') {
      setState(() {
        _phase = MeasuringPhase.measuring;
        _startedAt = DateTime.now();
        _elapsed = Duration.zero;
      });
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted || _startedAt == null) {
          return;
        }
        setState(() {
          _elapsed = DateTime.now().difference(_startedAt!);
        });
      });
    } else if (event.type == 'stopped') {
      _ticker?.cancel();
      unawaited(_sampler.stop());
      setState(() {
        _phase = MeasuringPhase.finished;
      });
      final history = event.locationHistory ?? const <GeoPoint>[];
      unawaited(_goToNameEntry(history));
    }
  }

  Future<void> _goToNameEntry(List<GeoPoint> history) async {
    final totalSeconds = history.length >= 2
        ? history.last.timestamp
                  .difference(history.first.timestamp)
                  .inMilliseconds /
              1000.0
        : 0.0;
    final nickname = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => NameEntryScreen(
          organizationDisplayName: widget.organizationDisplayName,
          totalSeconds: totalSeconds,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (nickname != null) {
      await widget.onFinished?.call(
        history,
        nickname.isEmpty ? '名称未設定' : nickname,
      );
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _arm() {
    _controller.pressStart();
    _sampler.start();
    setState(() {
      _armed = true;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_eventSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_sampler.stop());
    _controller.dispose();
    super.dispose();
  }

  String get _statusText {
    switch (_phase) {
      case MeasuringPhase.waitingStart:
        return _armed ? 'スタート地点への入域を待っています' : '開始ボタンを押してください';
      case MeasuringPhase.measuring:
        return '計測中';
      case MeasuringPhase.finished:
        return 'ゴールしました';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final minutes = _elapsed.inMinutes;
    final seconds = _elapsed.inSeconds % 60;
    final tenths = (_elapsed.inMilliseconds % 1000) ~/ 100;
    return Scaffold(
      appBar: AppBar(title: Text(widget.route.routeName)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.route.category, style: theme.textTheme.titleMedium),
              const SizedBox(height: 24),
              Text(_statusText, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.$tenths',
                style: theme.textTheme.displayMedium,
              ),
              const Spacer(),
              if (_phase == MeasuringPhase.waitingStart && !_armed)
                FilledButton(onPressed: _arm, child: const Text('計測開始')),
            ],
          ),
        ),
      ),
    );
  }
}
