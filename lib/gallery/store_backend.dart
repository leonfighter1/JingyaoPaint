// Picks where paintings are stored for the platform the app is running on:
// app files on Android/Windows, browser storage on the web.
export 'store_backend_io.dart'
    if (dart.library.js_interop) 'store_backend_web.dart';
