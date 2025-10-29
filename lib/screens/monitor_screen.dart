import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:developer' as developer;

import '../state/monitor_state.dart';
import '../widgets/temperature_gauge.dart';

class MonitorScreen extends StatelessWidget {
  const MonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<BabyMonitorState>();
    final theme = Theme.of(context);
    final bool offline = state.connectionStatus != ConnectionStatus.connected;
    final temperature = state.temperature;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        children: [
          ConnectionBanner(
            status: state.connectionStatus,
            label: state.connectionLabel,
            onTap: () => _showConnectionSheet(context),
          ),
          const SizedBox(height: 20),
          if (state.isMuted)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _MutedChip(remaining: state.muteRemaining),
            ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: offline ? 0.4 : 1,
            child: TemperatureCard(
              temperature: temperature,
              state: state,
            ),
          ),
          const SizedBox(height: 16),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: offline ? 0.4 : 1,
            child: CryCard(
              crying: state.crying,
              recentlyCrying: state.recentlyCrying,
              sinceLastCry: state.timeSinceLastCry,
            ),
          ),
          if (offline)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'Device offline. Values will refresh once connection returns.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }

  void _showConnectionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final state = context.read<BabyMonitorState>();
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connection',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                state.connectionLabel,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  state.requestReconnect();
                },
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Reconnect / Scan'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.close),
                label: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.status,
    required this.label,
    required this.onTap,
  });

  final ConnectionStatus status;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);

    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(BuildContext context, ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return const Color(0xFF2ECC71);
      case ConnectionStatus.reconnecting:
        return const Color(0xFFF39C12);
      case ConnectionStatus.disconnected:
        return const Color(0xFFE74C3C);
    }
  }
}

class TemperatureCard extends StatefulWidget {
  const TemperatureCard({
    super.key,
    required this.temperature,
    required this.state,
  });

  final double? temperature;
  final BabyMonitorState state;

  @override
  State<TemperatureCard> createState() => _TemperatureCardState();
}

class _TemperatureCardState extends State<TemperatureCard> {
  @override
  Widget build(BuildContext context) {
    developer.log('TemperatureCard.build - temp: ${widget.temperature}, alert: ${widget.state.tempAlert}', 
        name: 'TemperatureCard');
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final bool offline = widget.temperature == null;
    final status = widget.state.tempAlert;
    final statusLabel = offline
        ? 'Offline'
        : switch (status) {
            TempAlertStatus.ok => 'Comfort',
            TempAlertStatus.low => 'Too cold',
            TempAlertStatus.high => 'Too hot',
          };
    final statusColor = offline
        ? theme.colorScheme.onSurfaceVariant
        : switch (status) {
            TempAlertStatus.ok => theme.colorScheme.secondary,
            TempAlertStatus.low => const Color(0xFF2D8CFF),
            TempAlertStatus.high => const Color(0xFFD64545),
          };

    final statusChipBackground = offline
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.08)
        : statusColor.withValues(alpha: 0.1);

    final statusDotColor =
        offline ? statusColor.withValues(alpha: 0.5) : statusColor;

    final headlineTemperature = widget.temperature == null
        ? '--.- °C'
        : '${widget.temperature!.toStringAsFixed(1)} °C';

    final subtitle =   'Comfort ${widget.state.comfortMin.toStringAsFixed(0)}–${widget.state.comfortMax.toStringAsFixed(0)} °C';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Room temperature',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        headlineTemperature,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: labelColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TemperatureGauge(
              temperature: widget.temperature,
              minValue: 18,
              maxValue: 32,
              alertStatus: status,
              dimmed: offline,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: statusChipBackground,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: statusDotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    statusLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CryCard extends StatefulWidget {
  const CryCard({
    super.key,
    required this.crying,
    required this.recentlyCrying,
    required this.sinceLastCry,
  });

  final bool crying;
  final bool recentlyCrying;
  final Duration? sinceLastCry;

  @override
  State<CryCard> createState() => _CryCardState();
}

class _CryCardState extends State<CryCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color tint;
    final String headline;

    if (widget.crying) {
      tint = const Color(0xFFFFCDD2);
      headline = 'Crying now';
    } else if (widget.recentlyCrying) {
      tint = const Color(0xFFFFF4CC);
      headline = 'Recently crying';
    } else {
      tint = const Color(0xFFD5F5E3);
      headline = 'Calm';
    }

    return Card(
      child: Container(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _CryIcon(active: widget.crying),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _buildSubtitle(),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildSubtitle() {
    if (widget.crying) {
      if (widget.sinceLastCry == null) {
        return 'Crying detected just now';
      }
      return 'Crying for ${_formatDuration(widget.sinceLastCry!)}';
    }
    if (widget.sinceLastCry == null) {
      return 'No cry detected yet';
    }
    final formatted = _formatDuration(widget.sinceLastCry!);
    if (widget.recentlyCrying) {
      return 'Last cry $formatted ago';
    }
    return 'No cry in last $formatted';
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours >= 1) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      if (minutes > 0) {
        return '$hours h $minutes m';
      }
      return '$hours h';
    }
    if (duration.inMinutes >= 1) {
      final minutes = duration.inMinutes;
      return '$minutes min';
    }
    final seconds = duration.inSeconds;
    return '$seconds s';
  }
}

class _MutedChip extends StatelessWidget {
  const _MutedChip({required this.remaining});

  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = remaining == null
        ? 'Muted'
        : 'Muted ${_formatRemaining(remaining!)} left';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_off, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge,
          ),
        ],
      ),
    );
  }

  String _formatRemaining(Duration duration) {
    if (duration.inMinutes >= 1) {
      final minutes = duration.inMinutes;
      final seconds =
          duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }
    final seconds = duration.inSeconds;
    return '${seconds}s';
  }
}

class _CryIcon extends StatefulWidget {
  const _CryIcon({required this.active});

  final bool active;

  @override
  State<_CryIcon> createState() => _CryIconState();
}

class _CryIconState extends State<_CryIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.9,
      upperBound: 1.1,
    );
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _CryIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.active
        ? const Color(0xFFD64545)
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return ScaleTransition(
      scale: widget.active ? _controller : const AlwaysStoppedAnimation(1),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.graphic_eq,
          size: 28,
          color: color,
        ),
      ),
    );
  }
}
