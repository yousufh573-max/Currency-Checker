import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Captured photos live only in the app's private cache directory and are
/// deleted as soon as the next note is scanned, when the session ends, and on
/// every app start. Banknote images are never stored permanently.
class TempImageStore {
  TempImageStore(this.dir);
  final Directory dir;

  static Future<TempImageStore> create() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'captures'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    return TempImageStore(dir);
  }

  /// Moves a camera file into the private capture dir.
  Future<File> adopt(String path, String captureId) async {
    final src = File(path);
    final dst = File(p.join(dir.path, '$captureId.jpg'));
    try {
      return await src.rename(dst.path);
    } on FileSystemException {
      final copy = await src.copy(dst.path);
      await src.delete();
      return copy;
    }
  }

  Future<void> delete(File? f) async {
    if (f != null && await f.exists()) await f.delete();
  }

  Future<void> clearAll() async {
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      await e.delete(recursive: true);
    }
  }
}
