"""Generic reader for SQL Server data pages inside an uncompressed .bak file.

Groups records by (page object id, column count, fixed-length size) so that
each group is one table, and decodes variable-length columns as UTF-16 text.
"""
import struct, sys, json, collections

PAGE = 8192


def pages(buf):
    # pages in a backup stream are 8 KB aligned relative to the data stream,
    # whose start is 512-byte aligned; probe every 512 bytes.
    off = 0
    n = len(buf)
    while off + PAGE <= n:
        h = buf[off:off + 96]
        if h[0] == 1 and h[1] == 1:  # header version 1, type 1 = data page
            slot_cnt = struct.unpack_from('<H', h, 22)[0]
            free_data = struct.unpack_from('<H', h, 30)[0]
            obj = struct.unpack_from('<I', h, 24)[0]
            if 0 < slot_cnt < 1000 and 96 <= free_data <= PAGE:
                pg = buf[off:off + PAGE]
                slots = [struct.unpack_from('<H', pg, PAGE - 2 - 2 * i)[0] for i in range(slot_cnt)]
                if all(96 <= s < free_data for s in slots):
                    yield obj, pg, slots
                    off += PAGE
                    continue
        off += 512


def record(pg, s):
    st = pg[s]
    if st & 0x0E not in (0,):  # primary record only
        return None
    fixed_end = struct.unpack_from('<H', pg, s + 2)[0]
    if fixed_end < 4 or s + fixed_end + 2 > PAGE:
        return None
    fixed = pg[s + 4:s + fixed_end]
    ncols = struct.unpack_from('<H', pg, s + fixed_end)[0]
    if ncols == 0 or ncols > 300:
        return None
    nb = (ncols + 7) // 8
    p = s + fixed_end + 2
    nulls = pg[p:p + nb]
    p += nb
    var = []
    if st & 0x20:
        nvar = struct.unpack_from('<H', pg, p)[0]
        if nvar > ncols:
            return None
        ends = [struct.unpack_from('<H', pg, p + 2 + 2 * i)[0] for i in range(nvar)]
        start = p + 2 + 2 * nvar - s
        for e in ends:
            e &= 0x7FFF
            if e < start or s + e > PAGE:
                return None
            var.append(pg[s + start:s + e])
            start = e
    return ncols, fixed, nulls, var


def text(b):
    if len(b) % 2 == 0 and b:
        try:
            t = b.decode('utf-16le')
            if all(c.isprintable() or c in '\r\n\t' for c in t) and not any('\u3400' <= c <= '\ud7ff' for c in t):
                return t
        except UnicodeDecodeError:
            pass
    try:
        return b.decode('cp1256')
    except Exception:
        return b.hex()


def main(path, out):
    buf = open(path, 'rb').read()
    groups = collections.defaultdict(list)
    for obj, pg, slots in pages(buf):
        for s in slots:
            r = record(pg, s)
            if r is None:
                continue
            ncols, fixed, nulls, var = r
            groups[(obj, ncols, len(fixed))].append((fixed.hex(), [text(v) for v in var]))
    res = []
    for (obj, ncols, flen), rows in groups.items():
        seen = set()
        uniq = []
        for r in rows:
            k = (r[0], tuple(r[1]))
            if k not in seen:
                seen.add(k)
                uniq.append(r)
        res.append({'obj': obj, 'ncols': ncols, 'fixed': flen, 'rows': uniq})
    res.sort(key=lambda g: -len(g['rows']))
    json.dump(res, open(out, 'w'), ensure_ascii=False)
    for g in res[:400]:
        sample = next((r[1] for r in g['rows'] if r[1]), [])
        print(g['obj'], g['ncols'], g['fixed'], len(g['rows']), ' | '.join(x[:25] for x in sample[:6]))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
