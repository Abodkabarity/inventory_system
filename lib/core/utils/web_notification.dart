import 'dart:html' as html;

class WebNotification {
  static Future<void> init() async {
    if (html.Notification.permission != 'granted') {
      await html.Notification.requestPermission();
      print(html.Notification.permission);
    }
  }

  static void show({required String title, required String body}) {
    if (html.Notification.permission == 'granted') {
      html.Notification(title, body: body);
      print(html.Notification.permission);
    }
  }
}
