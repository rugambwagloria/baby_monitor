import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'dart:developer' as developer;

import '../state/monitor_state.dart';

class TemperatureGauge extends StatelessWidget {
  const TemperatureGauge({
    super.key,
    required this.temperature,
    required this.minValue,
    required this.maxValue,
    required this.alertStatus,
    this.dimmed = false,
  });

  final double? temperature;
  final double minValue;
  final double maxValue;
  final TempAlertStatus alertStatus;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    developer.log('TemperatureGauge.build - temp: $temperature, min: $minValue, max: $maxValue, alert: $alertStatus', 
        name: 'TemperatureGauge');
    final theme = Theme.of(context);
    final baseColor =
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.1);
    final color = _alertColor(theme, alertStatus);
    final gaugeColor = dimmed ? color.withValues(alpha: 0.3) : color;
    final progress = temperature == null
        ? null
        : ((temperature! - minValue) / (maxValue - minValue)).clamp(0.0, 1.0);

    return SizedBox(
      width: double.infinity,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GaugePainter(
                progress: progress,
                trackColor: baseColor,
                progressColor: gaugeColor,
                minValue: minValue,
                maxValue: maxValue,
              ),
            ),
          ),
          if (!dimmed && temperature != null)
            Positioned(
              bottom: 40,
              child: Column(
                children: [
                  Text(
                    '${minValue.toInt()}°',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: gaugeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getTemperatureIcon(temperature!),
                          size: 14,
                          color: gaugeColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${temperature!.toStringAsFixed(1)}°C',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: gaugeColor,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (!dimmed && temperature != null)
            Positioned(
              top: 40,
              right: 60,
              child: Text(
                '${maxValue.toInt()}°',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  IconData _getTemperatureIcon(double temp) {
    if (temp < 20) return Icons.ac_unit;
    if (temp < 24) return Icons.thermostat;
    if (temp < 28) return Icons.wb_sunny_outlined;
    return Icons.local_fire_department;
  }

  Color _alertColor(ThemeData theme, TempAlertStatus status) {
    switch (status) {
      case TempAlertStatus.ok:
        return theme.colorScheme.primary;
      case TempAlertStatus.low:
        return const Color(0xFF2D8CFF);
      case TempAlertStatus.high:
        return const Color(0xFFD64545);
    }
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.minValue,
    required this.maxValue,
  });

  final double? progress;
  final Color trackColor;
  final Color progressColor;
  final double minValue;
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 20.0;
    final startAngle = math.pi * 0.75; // 135° (bottom-left)
    final sweepAngle = math.pi * 1.5; // 270° (semi-circle)
    final center = Offset(size.width / 2, size.height * 0.7);
    final radius = size.width * 0.35;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;

    // Draw glow effect when there's progress
    if (progress != null && progress! > 0) {
      final glowPaint = Paint()
        ..color = progressColor.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth + 8
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      final arcRect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(arcRect, startAngle,
          sweepAngle * progress!.clamp(0.0, 1.0), false, glowPaint);
    }

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(arcRect, startAngle, sweepAngle, false, trackPaint);

    if (progress != null) {
      canvas.drawArc(arcRect, startAngle,
          sweepAngle * progress!.clamp(0.0, 1.0), false, progressPaint);

      // Draw marker at current position
      final markerAngle = startAngle + (sweepAngle * progress!.clamp(0.0, 1.0));
      final markerX = center.dx + radius * math.cos(markerAngle);
      final markerY = center.dy + radius * math.sin(markerAngle);
      
      final markerPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(Offset(markerX, markerY), strokeWidth / 2 + 2, markerPaint);
      
      final markerInnerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(Offset(markerX, markerY), strokeWidth / 2 - 4, markerInnerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue;
  }
}
