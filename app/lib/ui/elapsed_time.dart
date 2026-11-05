/// elapsed_time.dart — how long a transfer has been running.
///
/// A transfer over animated QR codes takes minutes, and how many is the
/// first thing anyone wants to know: whether to wait, whether to change
/// a setting, whether something is wrong. Without it the only evidence
/// of time passing was a frame counter.
library;

import 'dart:async';

import 'package:flutter/material.dart';

/// Formats a duration the way a stopwatch would: `0:42`, `3:05`,
/// `1:02:30`.
String formatElapsed(Duration d) {
  if (d.isNegative) return '0:00';
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// Shows the time since [since], ticking once a second.
///
/// Pass [frozenAt] once the transfer has ended, so the figure stops
/// rather than counting on past the thing it measures.
class ElapsedTime extends StatefulWidget {
  const ElapsedTime({
    super.key,
    required this.since,
    this.frozenAt,
    this.style,
  });

  final DateTime since;

  /// When the transfer finished. While null, the readout ticks.
  final DateTime? frozenAt;

  final TextStyle? style;

  @override
  State<ElapsedTime> createState() => _ElapsedTimeState();
}

class _ElapsedTimeState extends State<ElapsedTime> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(ElapsedTime old) {
    super.didUpdateWidget(old);
    if (widget.frozenAt != null) {
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null) {
      _start();
    }
  }

  void _start() {
    if (widget.frozenAt != null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = widget.frozenAt ?? DateTime.now();
    return Text(
      formatElapsed(end.difference(widget.since)),
      style: widget.style,
    );
  }
}
