import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:developer' as developer;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  
  // Track last notification times for each type
  DateTime? _lastCryNotificationTime;
  DateTime? _lastTempNotificationTime;
  static const Duration _cryNotificationBuffer = Duration(minutes: 1);
  static const Duration _tempNotificationBuffer = Duration(minutes: 3);

  Future<void> initialize() async {
    if (_initialized) return;

    developer.log('Initializing notification service', name: 'NotificationService');

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (details) {
        developer.log('Notification tapped: ${details.payload}', name: 'NotificationService');
      },
    );

    // Request notification permissions
    await _requestPermissions();
    
    _initialized = true;
    developer.log('Notification service initialized', name: 'NotificationService');
  }

  Future<void> _requestPermissions() async {
    developer.log('Requesting notification permissions', name: 'NotificationService');
    final status = await Permission.notification.request();
    developer.log('Notification permission status: $status', name: 'NotificationService');
    if (status.isDenied) {
      developer.log('Notification permission denied', name: 'NotificationService');
    }
  }

  Future<void> showCryAlert({
    required Duration duration,
    bool isMuted = false,
  }) async {
    developer.log('showCryAlert called - isMuted: $isMuted', name: 'NotificationService');
    if (isMuted) {
      developer.log('Cry alert skipped - muted', name: 'NotificationService');
      return;
    }

    // Check if we're within the 2-minute buffer
    final now = DateTime.now();
    if (_lastCryNotificationTime != null) {
      final timeSinceLastNotification = now.difference(_lastCryNotificationTime!);
      if (timeSinceLastNotification < _cryNotificationBuffer) {
        developer.log('Cry alert skipped - within 1 minute buffer (${timeSinceLastNotification.inSeconds}s since last)', 
            name: 'NotificationService');
        return;
      }
    }

    _lastCryNotificationTime = now;

    const androidDetails = AndroidNotificationDetails(
      'cry_alerts',
      'Cry Alerts',
      channelDescription: 'Notifications when baby is crying',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      ongoing: true,
      autoCancel: false,
      category: AndroidNotificationCategory.alarm,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      1, // Cry notification ID
      '👶 Baby is crying',
      'Crying for ${_formatDuration(duration)}',
      details,
    );
    developer.log('Cry alert shown - duration: ${_formatDuration(duration)}', name: 'NotificationService');
  }

  Future<void> clearCryAlert() async {
    await _notifications.cancel(1);
    // Reset the notification buffer when alert is cleared
    _lastCryNotificationTime = null;
  }

  Future<void> showTemperatureAlert({
    required String status,
    required double temperature,
    bool isMuted = false,
  }) async {
    developer.log('showTemperatureAlert called - status: $status, temp: $temperature, isMuted: $isMuted', 
        name: 'NotificationService');
    if (isMuted) {
      developer.log('Temperature alert skipped - muted', name: 'NotificationService');
      return;
    }

    // Check if we're within the 5-minute buffer
    final now = DateTime.now();
    if (_lastTempNotificationTime != null) {
      final timeSinceLastNotification = now.difference(_lastTempNotificationTime!);
      if (timeSinceLastNotification < _tempNotificationBuffer) {
        developer.log('Temperature alert skipped - within 5 minute buffer (${timeSinceLastNotification.inSeconds}s since last)', 
            name: 'NotificationService');
        return;
      }
    }

    _lastTempNotificationTime = now;

    final title = status == 'low' 
        ? '❄️ Temperature too low' 
        : '🔥 Temperature too high';
    
    const androidDetails = AndroidNotificationDetails(
      'temp_alerts',
      'Temperature Alerts',
      channelDescription: 'Notifications for temperature alerts',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      2, // Temperature notification ID
      title,
      'Room temperature: ${temperature.toStringAsFixed(1)}°C',
      details,
    );
    developer.log('Temperature alert shown - $title', name: 'NotificationService');
  }

  Future<void> clearTemperatureAlert() async {
    await _notifications.cancel(2);
    // Reset the notification buffer when alert is cleared
    _lastTempNotificationTime = null;
  }

  Future<void> showConnectionAlert({
    required bool isConnected,
  }) async {
    developer.log('showConnectionAlert called - isConnected: $isConnected', name: 'NotificationService');
    final title = isConnected ? '✅ Monitor connected' : '⚠️ Monitor disconnected';
    final body = isConnected 
        ? 'Baby monitor is now connected' 
        : 'Connection to baby monitor lost';

    const androidDetails = AndroidNotificationDetails(
      'connection_alerts',
      'Connection Alerts',
      channelDescription: 'Notifications for connection status changes',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      3, // Connection notification ID
      title,
      body,
      details,
    );
    developer.log('Connection alert shown - $title', name: 'NotificationService');
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
    return '$seconds sec';
  }
}
