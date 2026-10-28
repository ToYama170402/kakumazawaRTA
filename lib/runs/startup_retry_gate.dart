import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class StartupRetryGate extends StatefulWidget {
  const StartupRetryGate({
    super.key,
    required this.retryAction,
    required this.child,
  });

  final Future<void> Function() retryAction;
  final Widget child;

  @override
  State<StartupRetryGate> createState() => _StartupRetryGateState();
}

class _StartupRetryGateState extends State<StartupRetryGate> {
  bool _hasTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasTriggered) {
        return;
      }
      _hasTriggered = true;
      unawaited(_runRetryAction());
    });
  }

  Future<void> _runRetryAction() async {
    try {
      await widget.retryAction();
    } catch (error, stackTrace) {
      debugPrint('Startup retry failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
