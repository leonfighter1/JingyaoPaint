import 'package:web/web.dart' as web;

/// The browser's name from its user agent. Order matters: Edge and Chrome
/// both say "Chrome", and every iOS browser says "Safari".
String? browserName() {
  final ua = web.window.navigator.userAgent;
  if (ua.contains('Edg/') || ua.contains('EdgiOS')) return 'Edge';
  if (ua.contains('Firefox/') || ua.contains('FxiOS')) return 'Firefox';
  if (ua.contains('OPR/')) return 'Opera';
  if (ua.contains('CriOS') || ua.contains('Chrome/')) return 'Chrome';
  if (ua.contains('Safari/')) return 'Safari';
  return null;
}
