// Stub file to satisfy conditional import for firebase_messaging on web.
// Provides a minimal API surface used by the app so web builds don't fail.

class RemoteNotification {
  final String? title;
  final String? body;
  RemoteNotification({this.title, this.body});
}

class RemoteMessage {
  final Map<String, dynamic>? data;
  final RemoteNotification? notification;
  RemoteMessage({this.data, this.notification});
}

class FirebaseMessaging {
  FirebaseMessaging._();

  // Expose a static instance to match the real package API used in the app.
  static final FirebaseMessaging instance = FirebaseMessaging._();
  Future<String?> getToken() async => null;

  // Solicitar permisos (no-op en stub web)
  Future<void> requestPermission() async {}

  // Stream that emits when the FCM token is refreshed. Empty on web stub.
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  // Static stream for incoming messages (onMessage). Empty on web stub.
  static Stream<RemoteMessage> get onMessage =>
      const Stream<RemoteMessage>.empty();

  // Static stream for when a notification opens the app (no-op in stub).
  static Stream<RemoteMessage> get onMessageOpenedApp =>
      const Stream<RemoteMessage>.empty();
}

// Stub FcmService for web builds
class FcmService {
  static Future<void> initialize() async {
    // No-op on web
  }
}
