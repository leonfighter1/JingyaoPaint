// Picks where added music is kept for the platform the app is running on:
// app files on Android/Windows, memory on the web.
export 'music_files_io.dart'
    if (dart.library.js_interop) 'music_files_web.dart';
