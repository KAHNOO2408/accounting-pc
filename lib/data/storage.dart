import 'dart:convert';
import 'dart:io';

/// File based persistence. Data lives in %APPDATA%\TarazAccounting on Windows.
class Storage {
  final Directory dir;

  Storage(this.dir);

  static String get sep => Platform.pathSeparator;

  static Storage init() {
    final env = Platform.environment;
    String base;
    if (Platform.isWindows) {
      base = env['APPDATA'] ?? env['USERPROFILE'] ?? Directory.current.path;
    } else {
      base = env['HOME'] ?? Directory.current.path;
    }
    final dir = Directory('$base${sep}TarazAccounting');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return Storage(dir);
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
          if (j is Map<String, dynamic>) return j;
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
