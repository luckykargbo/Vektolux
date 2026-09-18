// lib/core/services/notification_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Firebase Cloud Messaging & Push Notification Service
// Handles FCM permissions, token lifecycle, background message entry-point,
// high-priority heads-up channels for Android, APNs options for iOS,
// and deep-link payload routing to the in-app Notification Center.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../network/convex_client_wrapper.dart';
import '../../features/notifications/presentation/views/notifications_screen.dart';
import '../../features/navigation/presentation/views/main_navigation_shell.dart';

// ─── Top-Level Background Message Handler ─────────────────────────────
// Must be an annotated top-level or static function for Dart entry-point.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Already initialized or platform fallback
  }
  debugPrint('[FCM Background] Received message: ${message.messageId} | ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  /// Global Navigator key used to route deep links from background/notification clicks
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  ConvexClientWrapper? _convexClient;
  String? _currentUserId;
  String? _fcmToken;
  bool _isInitialized = false;

  /// High-priority notification channel for Android heads-up alerts
  static const AndroidNotificationChannel _highPriorityChannel = AndroidNotificationChannel(
    'vektolux_high_importance',
    'Vektolux Alerts & Escrow Notices',
    description: 'High-priority heads-up alerts for escrow milestones, bookings, and broadcasts.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Initialize Firebase messaging, notification channels, and listeners
  Future<void> initialize({
    required ConvexClientWrapper convexClient,
    String? userId,
  }) async {
    _convexClient = convexClient;
    _currentUserId = userId;

    if (_isInitialized) {
      if (userId != null && userId.isNotEmpty) {
        await _registerTokenWithConvex();
      }
      return;
    }

    try {
      // 1. Initialize Firebase Core safely
      await Firebase.initializeApp();

      // 2. Set background messaging handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 3. Initialize local notification display plugin
      await _setupLocalNotifications();

      // 4. Request OS notification permissions
      await requestPermissions();

      // 5. Configure iOS foreground presentation
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 6. Subscribe to broadcast topic
      try {
        await FirebaseMessaging.instance.subscribeToTopic('all_users');
        debugPrint('[FCM] Subscribed to topic: all_users');
      } catch (e) {
        debugPrint('[FCM] Topic subscription note: $e');
      }

      // 7. Retrieve device token
      try {
        _fcmToken = await FirebaseMessaging.instance.getToken();
        debugPrint('[FCM] Device Token: $_fcmToken');
        if (_fcmToken != null && _currentUserId != null) {
          await _registerTokenWithConvex();
        }
      } catch (e) {
        debugPrint('[FCM] Token retrieval note: $e');
      }

      // 8. Listen for token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        if (_currentUserId != null) {
          _registerTokenWithConvex();
        }
      });

      // 9. Setup foreground and background notification click listeners
      _setupMessageListeners();

      _isInitialized = true;
      debugPrint('[FCM] NotificationService initialized successfully.');
    } catch (e) {
      debugPrint('[FCM] NotificationService setup completed with fallback: $e');
      _isInitialized = true;
    }
  }

  /// Update the authenticated user and sync FCM token
  Future<void> updateUser(String? userId) async {
    _currentUserId = userId;
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      await _registerTokenWithConvex();
    }
  }

  /// Request runtime system permissions
  Future<bool> requestPermissions() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');
      return granted;
    } catch (e) {
      debugPrint('[FCM] Permission request error: $e');
      return false;
    }
  }

  /// Setup local notification channels and plugin
  Future<void> _setupLocalNotifications() async {
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
    if (!kIsWeb && Platform.isAndroid) {
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(_highPriorityChannel);
      }
    }
  }

  /// Listen for incoming messages and notification taps
  void _setupMessageListeners() {
    // 1. Foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('[FCM Foreground] Message received: ${message.notification?.title}');
      final notification = message.notification;
      final android = message.notification?.android;

      if (notification != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _highPriorityChannel.id,
              _highPriorityChannel.name,
              channelDescription: _highPriorityChannel.description,
              icon: android?.smallIcon ?? '@mipmap/ic_launcher',
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
          payload: jsonEncode(message.data),
        );
      }
    });

    // 2. App opened from background notification tap
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM onMessageOpenedApp] User tapped notification: ${message.data}');
      _handleDeepLink(message.data);
    });

    // 3. App opened from terminated state via notification tap
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('[FCM getInitialMessage] Cold-start notification payload: ${message.data}');
        Future.delayed(const Duration(milliseconds: 1000), () {
          _handleDeepLink(message.data);
        });
      }
    });
  }

  /// Register device token with Convex backend
  Future<void> _registerTokenWithConvex() async {
    if (_convexClient == null || _currentUserId == null || _fcmToken == null) return;

    try {
      final deviceType = kIsWeb
          ? 'web'
          : Platform.isAndroid
              ? 'android'
              : Platform.isIOS
                  ? 'ios'
                  : 'desktop';

      await _convexClient!.mutation(
        'notifications:registerDeviceToken',
        args: {
          'userId': _currentUserId!,
          'fcmToken': _fcmToken!,
          'deviceType': deviceType,
          'topics': ['all_users'],
        },
      );
      debugPrint('[FCM] Registered token with Convex for user: $_currentUserId');
    } catch (e) {
      debugPrint('[FCM] Token sync error: $e');
    }
  }

  /// Deep-link parser and route executor
  void _handleDeepLink(Map<String, dynamic> data) {
    final screen = data['deepLinkScreen'] as String? ?? 'notifications';
    final id = data['deepLinkId'] as String?;
    debugPrint('[FCM DeepLink] Screen: $screen, ID: $id');

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
