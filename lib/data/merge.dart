/// Record-level three-way merge of the data file, so several computers can
/// save the shared books at the same time (like Sakan's SQL server): each
/// side's added, edited and deleted records are kept; a record edited on both
/// sides is merged field by field (this computer wins a field both changed).
library;

import 'dart:convert';

String _k(Object? v) => jsonEncode(v);
bool _same(Object? a, Object? b) => _k(a) == _k(b);

Object? merge3(Object? base, Object? local, Object? remote) {
  if (_same(local, base)) return remote;
  if (_same(remote, base)) return local;
  if (local is Map<String, dynamic> && remote is Map<String, dynamic>) {
    return mergeMaps(base is Map<String, dynamic> ? base : const {}, local, remote);
  }
  if (local is List && remote is List) return mergeLists(base is List ? base : const [], local, remote);
  return local;
}

Map<String, dynamic> mergeMaps(Map<String, dynamic> base, Map<String, dynamic> local, Map<String, dynamic> remote) {
  final out = <String, dynamic>{};
  for (final key in {...remote.keys, ...local.keys}) {
    final inL = local.containsKey(key), inR = remote.containsKey(key), inB = base.containsKey(key);
    if (inL && inR) {
      out[key] = merge3(base[key], local[key], remote[key]);
    } else if (inL) {
      // removed remotely, or added locally
      if (!inB || !_same(local[key], base[key])) out[key] = local[key];
    } else {
      if (!inB || !_same(remote[key], base[key])) out[key] = remote[key];
    }
  }
  return out;
}

String? _id(Object? e) => e is Map && e['id'] is String && (e['id'] as String).isNotEmpty ? e['id'] as String : null;

List<dynamic> mergeLists(List<dynamic> base, List<dynamic> local, List<dynamic> remote) {
  final keyed = [...base, ...local, ...remote].every((e) => _id(e) != null);
  String key(Object? e) => keyed ? _id(e)! : _k(e);
  Map<String, Object?> index(List<dynamic> l) => {for (final e in l) key(e): e};
  final b = index(base), l = index(local), r = index(remote);
  final out = <dynamic>[];
  final seen = <String>{};
  void consider(String k) {
    if (!seen.add(k)) return;
    final inB = b.containsKey(k), inL = l.containsKey(k), inR = r.containsKey(k);
    if (inL && inR) {
      out.add(merge3(b[k], l[k], r[k]));
    } else if (inL) {
      if (!inB || !_same(l[k], b[k])) out.add(l[k]); // added here, or edited here while deleted there
    } else if (inR) {
      if (!inB || !_same(r[k], b[k])) out.add(r[k]);
    }
  }

  for (final e in remote) {
    consider(key(e));
  }
  for (final e in local) {
    consider(key(e));
  }
  return out;
}

/// Document numbers that both computers gave out at the same time: the
/// records added here are moved to the next free number.
void renumberCollisions(Map<String, dynamic> merged, Map<String, dynamic> base, Map<String, dynamic> remote) {
  void fix(String list, List<String> fields, [List<String> group = const []]) {
    final items = merged[list];
    if (items is! List) return;
    final baseIds = {for (final e in (base[list] as List? ?? const [])) _id(e)};
    final remoteIds = {for (final e in (remote[list] as List? ?? const [])) _id(e)};
    for (final f in fields) {
      final used = <String, Set<int>>{};
      final maxOf = <String, int>{};
      String g(Map e) => group.map((x) => '${e[x]}').join('|');
      // numbers of records already known (base / other computer) are kept
      for (final e in items.whereType<Map>()) {
        if (!baseIds.contains(_id(e)) && !remoteIds.contains(_id(e))) continue;
        final n = e[f];
        if (n is int) {
          (used[g(e)] ??= {}).add(n);
          if (n > (maxOf[g(e)] ?? 0)) maxOf[g(e)] = n;
        }
      }
      for (final e in items.whereType<Map>()) {
        if (baseIds.contains(_id(e)) || remoteIds.contains(_id(e))) continue;
        final n = e[f];
        if (n is! int) continue;
        final set = used[g(e)] ??= {};
        if (set.contains(n)) {
          final next = [maxOf[g(e)] ?? 0, ...set].reduce((a, b) => a > b ? a : b) + 1;
          e[f] = next;
          set.add(next);
          maxOf[g(e)] = next;
        } else {
          set.add(n);
          if (n > (maxOf[g(e)] ?? 0)) maxOf[g(e)] = n;
        }
      }
    }
  }

  fix('invoices', ['number'], ['kind', 'proforma']);
  fix('vouchers', ['number', 'fixedNumber']);
  fix('settleDocs', ['number']);
  fix('productions', ['number']);
  fix('guarantees', ['number'], ['received']);
  fix('receptions', ['number']);
  fix('balanceDeals', ['number'], ['isReturn']);
  fix('people', ['code']);
  fix('warranties', ['code']);
}
