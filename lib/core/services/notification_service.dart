// lib/core/services/notification_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — In-App & Local Notification Service
// Handles local notification channels, heads-up alerts, deep-link routing,
// and navigation into the in-app Notification Center without external Firebase/APNs.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../network/convex_client_wrapper.dart';
import '../../features/notifications/presentation/views/notifications_screen.dart';
import '../../features/navigation/presentation/views/main_navigation_shell.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  /// Global Navigator key used to route deep links from notification clicks
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  ConvexClientWrapper? _convexClient;
  String? _currentUserId;
  bool _isInitialized = false;

  /// High-priority notification channel for Android heads-up alerts
  static const AndroidNotificationChannel _highPriorityChannel = AndroidNotificationChannel(
    'vektolux_high_importance',
    'Vektolux Alerts & Escrow Notices',
    description: 'High-priority alerts for escrow milestones, bookings, and broadcasts.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Initialize local notification channels and click listeners
  Future<void> initialize({
    required ConvexClientWrapper convexClient,
    String? userId,
  }) async {
    _convexClient = convexClient;
    _currentUserId = userId;

    if (_isInitialized) return;

    try {
      await _setupLocalNotifications();
      _isInitialized = true;
      debugPrint('[NotificationService] Local notifications initialized successfully.');
    } catch (e) {
      debugPrint('[NotificationService] Local notification setup completed with fallback: $e');
      _isInitialized = true;
    }
  }

  /// Update the authenticated user
  Future<void> updateUser(String? userId) async {
    _currentUserId = userId;
  }

  /// Request runtime system permissions for notifications
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidImpl = _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidImpl?.requestNotificationsPermission();
        return granted ?? false;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosImpl = _localNotifications
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        final granted = await iosImpl?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }
      return false;
    } catch (e) {
      debugPrint('[NotificationService] Permission request notice: $e');
      return false;
    }
  }

  /// Display a local notification banner
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) return;

    try {
      await _localNotifications.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _highPriorityChannel.id,
            _highPriorityChannel.name,
            channelDescription: _highPriorityChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[NotificationService] showNotification error: $e');
    }
  }

  /// Setup local notification channels and plugin
  Future<void> _setupLocalNotifications() async {
    if (kIsWeb) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            _handleDeepLink(data);
          } catch (_) {
            _navigateToNotificationCenter();
          }
        } else {
          _navigateToNotificationCenter();
        }
      },
    );

    // Create high-importance notification channel on Android
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(_highPriorityChannel);
      }
    }
  }

  /// Deep-link parser and route executor
  void _handleDeepLink(Map<String, dynamic> data) {
    final screen = data['deepLinkScreen'] as String? ?? 'notifications';
    final id = data['deepLinkId'] as String?;
    debugPrint('[NotificationService DeepLink] Screen: $screen, ID: $id');

    final context = navigatorKey.currentContext;
    if (context == null) return;

    switch (screen.toLowerCase()) {
      case 'notifications':
        _navigateToNotificationCenter();
        break;
      case 'home':
        MainNavigationShell.switchToTab(context, 0);
        break;
      case 'real_estate':
        MainNavigationShell.switchToTab(context, 2);
        break;
      case 'mobility':
        MainNavigationShell.switchToTab(context, 3);
        break;
      case 'profile':
        MainNavigationShell.switchToTab(context, 4);
        break;
      case 'escrow_real_estate':
      case 'escrow_vehicle':
        _navigateToNotificationCenter();
        break;
      default:
        _navigateToNotificationCenter();
        break;
    }
  }

  void _navigateToNotificationCenter() {
    final nav = navigatorKey.currentState;
    if (nav == null || _convexClient == null) return;

    nav.push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          convexClient: _convexClient!,
          currentUserId: _currentUserId,
        ),
      ),
    );
  }
}
