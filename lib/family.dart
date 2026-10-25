import 'gallery/painting_store.dart';
import 'music/music_library.dart';
import 'painting_session.dart';
import 'settings.dart';

/// The kids who use the app, each with their own paintings: switching
/// between them, adding and removing kids, and starting over.
///
/// Settings remember who the kids are; their paintings sit side by side in
/// one storage, told apart by [Kid.storePrefix].
class Family {
  Family({
    required this.settings,
    required this.backend,
    required this.session,
    required this.music,
  });

  final AppSettings settings;
  final StoreBackend backend;
  final PaintingSession session;
  final MusicLibrary music;

  static PaintingStore storeFor(StoreBackend backend, Kid kid) =>
      PaintingStore(kid.storePrefix.isEmpty
          ? backend
          : PrefixedStoreBackend(backend, kid.storePrefix));

  /// Saves the open painting and shows [kidId]'s paintings.
  Future<bool> switchTo(String kidId) async {
    if (kidId == settings.currentKid.id) return true;
    // Save under the current kid before the settings move on.
    if (!await session.save()) return false;
    settings.currentKidId = kidId;
    return session.switchStore(storeFor(backend, settings.currentKid));
  }

  /// Adds a kid and switches to them.
  Future<Kid> addKid(String name) async {
    final kid = settings.addKid(name);
    await switchTo(kid.id);
    return kid;
  }

  /// Deletes [kidId] and all their paintings. The last kid stays; resetting
  /// the app is the way to start over.
  Future<void> removeKid(String kidId) async {
    final kids = settings.kids;
    if (kids.length < 2) return;
    final kid = kids.firstWhere((k) => k.id == kidId);
    if (settings.currentKid.id == kidId) {
      await switchTo(kids.firstWhere((k) => k.id != kidId).id);
    }
    await storeFor(backend, kid).deleteAll();
    settings.removeKid(kidId);
  }

  /// Deletes every kid's paintings, the added music and all settings: the
  /// app starts again from the first-start setup.
  Future<void> resetAll() async {
    // Let a pending autosave finish now, not after the paintings are gone.
    await session.save();
    for (final kid in settings.kids) {
      await storeFor(backend, kid).deleteAll();
    }
    for (final track in [...music.added]) {
      await music.remove(track);
    }
    await settings.resetAll();
    await session.switchStore(storeFor(backend, settings.currentKid),
        saveFirst: false);
  }
}
