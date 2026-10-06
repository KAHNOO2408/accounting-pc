import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Compressed (and optionally password-protected) backup files.

const backupEntryName = 'taraz-data.json';

/// Thrown when a protected backup is opened without (or with a wrong) password.
class BackupPasswordException implements Exception {
  final bool wrong;
  const BackupPasswordException({this.wrong = false});

  @override
  String toString() => wrong ? 'رمز فایل پشتیبان اشتباه است' : 'این فایل پشتیبان رمز دارد';
}

/// Zips [json] (deflate; AES-256 when [password] is not empty).
Uint8List zipBackup(String json, {String password = ''}) {
  final a = Archive()..addFile(ArchiveFile.string(backupEntryName, json));
  return ZipEncoder(password: password.isEmpty ? null : password).encodeBytes(a);
}

/// True when the first entry of the zip is encrypted.
bool zipIsEncrypted(List<int> bytes) =>
    bytes.length > 8 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04 && (bytes[6] & 1) != 0;

/// Returns the JSON text inside a backup zip.
String unzipBackup(List<int> bytes, {String? password}) {
  final enc = zipIsEncrypted(bytes);
  if (enc && (password == null || password.isEmpty)) throw const BackupPasswordException();
  try {
    final a = ZipDecoder().decodeBytes(bytes, password: enc ? password : null);
    ArchiveFile? f = a.findFile(backupEntryName);
    if (f == null) {
      for (final x in a.files) {
        if (x.isFile && x.name.toLowerCase().endsWith('.json')) {
          f = x;
          break;
        }
      }
    }
    if (f == null) throw const FormatException('فایل اطلاعات در پشتیبان پیدا نشد');
    final text = utf8.decode(f.content);
    if (enc && !text.trimLeft().startsWith('{')) throw const BackupPasswordException(wrong: true);
    return text;
  } on BackupPasswordException {
    rethrow;
  } on FormatException {
    if (enc) throw const BackupPasswordException(wrong: true);
    rethrow;
  } catch (_) {
    if (enc) throw const BackupPasswordException(wrong: true);
    throw const FormatException('فایل پشتیبان فشرده معتبر نیست');
  }
}
