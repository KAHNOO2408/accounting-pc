import 'dart:convert';
import 'dart:io';

/// File based persistence. Data lives in %APPDATA%\TarazAccounting on Windows.
class Storage {
  final Directory dir;

  Storage(this.dir);

  static String get sep => Platform.pathSeparator;

  /// This computer's own data folder (%APPDATA%\TarazAccounting).
  static Directory get localDir {
    final env = Platform.environment;
    String base;
    if (Platform.isWindows) {
      base = env['APPDATA'] ?? env['USERPROFILE'] ?? Directory.current.path;
    } else {
      base = env['HOME'] ?? Directory.current.path;
    }
    final dir = Directory('$base${sep}TarazAccounting');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static File get _serverFile => File('${localDir.path}${sep}server.json');

  /// «اتصال به سرور»: a shared folder (e.g. \\PC1\Taraz) used instead of the
  /// local data, so several computers work on the same books.
  static String? get serverPath {
    try {
      if (!_serverFile.existsSync()) return null;
      final j = jsonDecode(_serverFile.readAsStringSync());
      final p = j is Map ? '${j['path'] ?? ''}' : '';
      return p.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }

  static set serverPath(String? p) {
    if (p == null || p.trim().isEmpty) {
      if (_serverFile.existsSync()) _serverFile.deleteSync();
    } else {
      _serverFile.writeAsStringSync(jsonEncode({'path': p.trim()}), flush: true);
    }
  }

  /// True when the data folder is the shared server folder.
  static bool get networked {
    final p = serverPath;
    return p != null && Directory(p).existsSync();
  }

  static Storage init() {
    final p = serverPath;
    if (p != null) {
      try {
        final d = Directory(p);
        if (d.existsSync()) return Storage(d);
      } catch (_) {}
    }
    return Storage(localDir);
  }

  // ------------------------------------------------ concurrent use (network)

  String _stamp = '';

  String _currentStamp() {
    try {
      final st = dataFile.statSync();
      return st.type == FileSystemEntityType.notFound ? '' : '${st.modified.millisecondsSinceEpoch}:${st.size}';
    } catch (_) {
      return '';
    }
  }

  /// Another computer saved the data after we last read or wrote it.
  bool changedExternally() => _stamp.isNotEmpty && _currentStamp() != _stamp;

  /// Exclusive write lock between computers (data.lock). Stale locks (older
  /// than 15 s) are taken over. Returns false if the lock was not obtained.
  bool lock({Duration wait = const Duration(seconds: 4)}) {
    final f = File('${dir.path}${sep}data.lock');
    final end = DateTime.now().add(wait);
    while (true) {
      try {
        f.createSync(exclusive: true);
        f.writeAsStringSync(Platform.localHostname);
        return true;
      } catch (_) {
        try {
          if (f.existsSync() && DateTime.now().difference(f.lastModifiedSync()).inSeconds > 15) {
            f.deleteSync();
            continue;
          }
        } catch (_) {}
        if (DateTime.now().isAfter(end)) return false;
        sleep(const Duration(milliseconds: 60));
      }
    }
  }

  void unlock() {
    try {
      final f = File('${dir.path}${sep}data.lock');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Name of the computer that saved last (written next to the data).
  File get _writerFile => File('${dir.path}${sep}last-writer.txt');
  String get lastWriter {
    try {
      return _writerFile.existsSync() ? _writerFile.readAsStringSync().trim() : '';
    } catch (_) {
      return '';
    }
  }

  File get dataFile => File('${dir.path}${sep}data.json');
  Directory get backupDir => Directory('${dir.path}${sep}backups');

  /// User-visible folder for exports & manual backups (Documents\Taraz).
  static Directory get userFolder {
    final env = Platform.environment;
    final home = Platform.isWindows ? (env['USERPROFILE'] ?? Directory.current.path) : (env['HOME'] ?? '.');
    final d = Directory('$home${sep}Documents${sep}Taraz');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Map<String, dynamic>? read() {
    for (final f in [dataFile, File('${dataFile.path}.bak')]) {
      try {
        if (f.existsSync()) {
          final txt = f.readAsStringSync();
          if (txt.trim().isEmpty) continue;
          final j = jsonDecode(txt);
          if (j is Map<String, dynamic>) {
            if (f.path == dataFile.path) _stamp = _currentStamp();
            return j;
          }
        }
      } catch (_) {
        // try the next candidate
      }
    }
    return null;
  }

  void save(Map<String, dynamic> data) {
    final txt = const JsonEncoder.withIndent(' ').convert(data);
    final tmp = File('${dataFile.path}.tmp');
    tmp.writeAsStringSync(txt, flush: true);
    try {
      if (dataFile.existsSync()) {
        dataFile.copySync('${dataFile.path}.bak');
      }
      tmp.renameSync(dataFile.path);
    } catch (_) {
      dataFile.writeAsStringSync(txt, flush: true);
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
    }
    _stamp = _currentStamp();
    try {
      _writerFile.writeAsStringSync('${Platform.localHostname} ${DateTime.now().toIso8601String()}');
    } catch (_) {}
  }

  /// A one-off copy of the data file before a format change (never deleted).
  void backupBefore(String tag) {
    try {
      if (!dataFile.existsSync()) return;
      if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
      final target = File('${backupDir.path}${sep}before-$tag.json');
      if (!target.existsSync()) dataFile.copySync(target.path);
    } catch (_) {}
  }

  /// Keeps one automatic backup per day, last [keep] days.
  void dailyBackup({int keep = 20}) {
    try {
      if (!dataFile.existsSync()) return;
      if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
      final n = DateTime.now();
      final stamp =
          '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
      final target = File('${backupDir.path}${sep}auto-$stamp.json');
      if (!target.existsSync()) dataFile.copySync(target.path);
      final files = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.split(sep).last.startsWith('auto-'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final f in files.skip(keep)) {
        f.deleteSync();
      }
    } catch (_) {}
  }

  static Future<void> openFolder(String path) async {
    try {
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {}
  }
}
