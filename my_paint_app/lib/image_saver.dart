// Picks the right way to save a PNG for the platform the app is running on:
// the gallery on Android/Windows, a browser download on the web.
export 'image_saver_io.dart'
    if (dart.library.js_interop) 'image_saver_web.dart';
