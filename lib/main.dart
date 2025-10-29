import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/monitor_screen.dart';
import 'screens/settings_screen.dart';
import 'state/monitor_state.dart';
import 'theme.dart';

void main() {
  runApp(const SmartBabyApp());
}

class SmartBabyApp extends StatelessWidget {
  const SmartBabyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BabyMonitorState(),
      child: Consumer<BabyMonitorState>(
        builder: (context, state, _) {
          return MaterialApp(
            title: 'Baby Monitor',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.themeData(state.themeType),
            home: const RootShell(),
          );
        },
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final monitorState = context.watch<BabyMonitorState>();
    final screens = const [
      MonitorScreen(key: ValueKey('monitor')),
      SettingsScreen(key: ValueKey('settings')),
    ];

    final floatingActionButton = _selectedIndex == 0
        ? FloatingActionButton.extended(
            onPressed: () =>
                monitorState.toggleMute(const Duration(minutes: 5)),
            icon: Icon(
              monitorState.isMuted
                  ? Icons.notifications_off
                  : Icons.notifications_active_outlined,
            ),
            label: Text(monitorState.isMuted ? 'Unmute' : 'Mute 5 min'),
          )
        : null;

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: screens[_selectedIndex],
      ),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            selectedIcon: Icon(Icons.monitor_heart),
            label: 'Monitor',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
