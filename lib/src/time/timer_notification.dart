import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// What a notification action asks for; the sync layer decides what to do.
enum TimerNotificationAction { open, pause, log }

typedef TimerActionHandler =
    void Function(TimerNotificationAction action, int issueId);

/// One ongoing, silent notification while a timer runs — a reminder, not a
/// correctness requirement (timers are wall-clock anchored and survive
/// anything). Android renders the elapsed time as a live system chronometer
/// so the notification never needs re-posting; iOS has no persistent
/// status-bar affordance, so it shows a quiet entry in the notification
/// center (a Live Activity is a possible later enhancement).
class TimerNotifications {
  TimerNotifications({
    FlutterLocalNotificationsPlugin? plugin,
    required this.pauseLabel,
    required this.logLabel,
    required this.channelName,
    required this.channelDescription,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final String pauseLabel;
  final String logLabel;
  final String channelName;
  final String channelDescription;

  static const _notificationId = 71;
  static const _channelId = 'running_timer';
  static const _categoryId = 'georeport_timer';

  Future<void>? _initializing;

  /// Both actions open the app (showsUserInterface): handling them in the
  /// main isolate keeps the timer store single-writer, at the cost of the
  /// app coming to the foreground on Pause. A background-isolate handler
  /// would need its own store access; deliberate v1 trade-off.
  ///
  /// Memoized as a future, so callers racing at startup all await the same
  /// initialization instead of the second one skipping past it.
  Future<void> init(TimerActionHandler onAction) =>
      _initializing ??= _initialize(onAction);

  Future<void> _initialize(TimerActionHandler onAction) async {
    await _plugin.initialize(
      settings: InitializationSettings(
        // Not the launcher icon: Android masks a notification's small icon
        // to its alpha channel, and the opaque launcher mipmap renders as a
        // solid white square in the status bar.
        android: const AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          // Asked lazily when the first timer starts, not at app launch.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _categoryId,
              actions: [
                DarwinNotificationAction.plain('pause', pauseLabel),
                DarwinNotificationAction.plain(
                  'log',
                  logLabel,
                  options: {DarwinNotificationActionOption.foreground},
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final issueId = int.tryParse(response.payload ?? '');
        if (issueId == null) {
          return;
        }
        onAction(switch (response.actionId) {
          'pause' => TimerNotificationAction.pause,
          'log' => TimerNotificationAction.log,
          _ => TimerNotificationAction.open,
        }, issueId);
      },
    );
  }

  /// Asks for notification permission; safe to call repeatedly (the system
  /// only prompts once). A denial is respected silently: show() simply does
  /// nothing visible and the app works exactly as before.
  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true);
  }

  Future<void> showRunning({
    required int issueId,
    required String subject,
    required DateTime runningSince,
  }) async {
    await _plugin.show(
      id: _notificationId,
      title: '#$issueId $subject',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          channelName,
          channelDescription: channelDescription,
          // A quiet, pinned reminder: no sound, no heads-up, not clearable.
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          category: AndroidNotificationCategory.stopwatch,
          // The system ticks the elapsed time itself; the notification is
          // posted once per state change, never per second.
          usesChronometer: true,
          showWhen: true,
          when: runningSince.millisecondsSinceEpoch,
          actions: [
            AndroidNotificationAction(
              'pause',
              pauseLabel,
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'log',
              logLabel,
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: _categoryId,
          // A silent banner confirms the running timer at start and the
          // entry stays in the notification center as the reminder.
          presentBanner: true,
          presentList: true,
          presentSound: false,
        ),
      ),
      payload: '$issueId',
    );
  }

  Future<void> clear() => _plugin.cancel(id: _notificationId);
}
