import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/monitor_state.dart';

class TipsScreen extends StatefulWidget {
  const TipsScreen({super.key});

  @override
  State<TipsScreen> createState() => _TipsScreenState();
}

class _TipsScreenState extends State<TipsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const List<Map<String, String>> _tips = [
    {
      'title': 'Safe sleep',
      'body':
          'Place baby on their back in a clear crib without loose bedding, pillows, or toys. Keep the room at a comfortable temperature.'
    },
    {
      'title': 'Feeding cues',
      'body':
          'Look for early feeding cues: lip smacking, rooting, hand-to-mouth — try to feed before crying begins.'
    },
    {
      'title': 'Soothing',
      'body':
          'Gentle rocking, swaddling (for young infants), white noise, and rhythmic pats can help calm a crying baby.'
    },
    {
      'title': 'Temperature',
      'body':
          'Aim for a comfortable room temperature and dress baby in one more layer than you would wear. Use the monitor to check room temp.'
    },
    {
      'title': 'Bonding',
      'body':
          'Skin-to-skin contact and eye contact during quiet alert times supports attachment and soothes your baby.'
    },
    {
      'title': 'When to call',
      'body':
          'If your baby has difficulty breathing, bluish lips, a fever in young infants, or a prolonged inconsolable cry, seek medical help.'
    },
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Map<String, dynamic> _computeInsights(BabyMonitorState state) {
    final now = DateTime.now();
    final recentWindow = const Duration(hours: 24);
    final recentEvents = state.events.where((e) => now.difference(e.timestamp) <= recentWindow).toList();

    final recentCries = recentEvents
        .where((e) => e.message.toLowerCase().contains('cry detected'))
        .length;
    final tempHighCount = recentEvents
        .where((e) => e.message.toLowerCase().contains('temperature high'))
        .length;
    final tempLowCount = recentEvents
        .where((e) => e.message.toLowerCase().contains('temperature low'))
        .length;

    final List<String> recommendations = [];
    String summary = 'No immediate issues detected from recent data.';
    String metricLabel = 'Status';
    String metricValue = '';

    // Temperature-based insights
    final temp = state.temperature;
    if (temp != null) {
      metricLabel = 'Room temp';
      metricValue = '${temp.toStringAsFixed(1)} °C';
      if (temp > state.comfortMax) {
        summary = 'Room temperature is above your comfort range.';
        recommendations.add('Remove a layer from the baby and improve ventilation.');
        recommendations.add('Check for direct sunlight or heating near the crib.');
        recommendations.add('Adjust comfort range in Settings if needed.');
      } else if (temp < state.comfortMin) {
        summary = 'Room temperature is below your comfort range.';
        recommendations.add('Add a light layer to the baby or raise room temperature slightly.');
        recommendations.add('Ensure baby isn\'t near drafts or open windows.');
      } else {
        summary = 'Temperature is within the configured comfort range.';
        if (tempHighCount > 0 || tempLowCount > 0) {
          recommendations.add('Device recorded ${tempHighCount + tempLowCount} temp alerts in the last 24 hours. Review recent readings.');
        }
      }
    } else {
      metricLabel = 'Device';
      metricValue = state.connectionStatus == ConnectionStatus.connected ? 'Connected' : 'Offline';
      if (state.connectionStatus != ConnectionStatus.connected) {
        summary = 'Device is offline — live readings are unavailable.';
        recommendations.add('Ensure the monitor has power and Bluetooth is enabled on your phone.');
      }
    }

    // Cry-based insights
    if (state.crying) {
      recommendations.insert(0, 'Baby is crying now — try feeding, checking diaper, or soothing techniques (rocking, white noise).');
      summary = 'Baby is currently crying.';
    } else if (recentCries > 0) {
      metricLabel = 'Cries (24h)';
      metricValue = '$recentCries';
      if (recentCries >= 3) {
        recommendations.add('Several cry events detected recently — consider tracking feed/sleep/diaper patterns.');
        recommendations.add('If cries are inconsolable or accompanied by fever, seek medical advice.');
      } else {
        recommendations.add('Occasional crying detected — try comforting techniques when it starts.');
      }
    }

    return {
      'summary': summary,
      'metricLabel': metricLabel,
      'metricValue': metricValue,
      'recommendations': recommendations,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<BabyMonitorState>();
    final insights = _computeInsights(state);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Care tips',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Practical tips for everyday care.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                height: 110,
                child: _AnimatedBaby(controllerProvider: () => _controller),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Personalized recommendations based on recent device data
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Personalized advice',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text(
                                insights['summary']!,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(insights['metricLabel']!,
                                style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(insights['metricValue']!,
                                style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary)),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (insights['recommendations'] != null &&
                        (insights['recommendations'] as List).isNotEmpty)
                      ...((insights['recommendations'] as List<String>)
                          .map((r) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.arrow_right, size: 18, color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(r, style: theme.textTheme.bodyMedium)),
                                  ],
                                ),
                              ))),
                  ],
                ),
              ),
            ),
          ),

          // Generic tips list
          ..._tips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t['title']!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t['body']!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              )),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Helpful reminders',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('- Check the room temperature regularly.',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('- Keep monitoring volume at a comfortable level.',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('- Keep the crib free from loose items for sleep safety.',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }
}

class _AnimatedBaby extends StatelessWidget {
  const _AnimatedBaby({Key? key, required this.controllerProvider}) : super(key: key);

  final AnimationController Function() controllerProvider;

  @override
  Widget build(BuildContext context) {
    final controller = controllerProvider();
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // generate values based on controller value
        final t = controller.value;
        final double bob = math.sin(t * math.pi * 2) * 6; // vertical bob
        final double rotate = math.sin(t * math.pi * 2) * 0.08; // small rotation

        return Stack(
          alignment: Alignment.center,
          children: [
            // small balloon floating to the top-left
            Positioned(
              left: 6,
              top: 8 - bob / 3,
                child: Transform.rotate(
                angle: rotate * 2,
                child: Icon(Icons.celebration, size: 22, color: Colors.pink[200]),
              ),
            ),
            Transform.translate(
              offset: Offset(0, -bob),
              child: Transform.rotate(
                angle: rotate,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      Icons.child_care,
                      size: 44,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            // tiny pacifier rotation near the baby
            Positioned(
              right: 6,
              bottom: 6 + bob / 4,
              child: Transform.rotate(
                angle: rotate * -3,
                child: Icon(Icons.circle, size: 12, color: Colors.orange[200]),
              ),
            ),
          ],
        );
      },
    );
  }
}
