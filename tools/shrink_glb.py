#!/usr/bin/env python3
"""Downscale every embedded texture in a .glb so its long edge is at most
1024 px, rewriting the binary chunk in place of the original images.

usage: python3 tools/shrink_glb.py in.glb out.glb [max_px]
"""

import io
import json
import struct
import sys

from PIL import Image


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2, "not a glTF 2 binary"
    off = 12
    js, bin_ = None, b""
    while off < len(data):
        length, kind = struct.unpack_from("<I4s", data, off)
        chunk = data[off + 8: off + 8 + length]
        if kind == b"JSON":
            js = json.loads(chunk)
        elif kind == b"BIN\x00":
            bin_ = chunk
        off += 8 + length
    return js, bin_


def pad4(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    max_px = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    js, bin_ = read_glb(src)
    views = js.get("bufferViews", [])
    replaced = {}
    for img in js.get("images", []):
        if "bufferView" not in img:
            continue
        v = views[img["bufferView"]]
        raw = bin_[v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]
        im = Image.open(io.BytesIO(raw))
        w, h = im.size
        if max(w, h) <= max_px:
            continue
        s = max_px / max(w, h)
        im = im.resize((round(w * s), round(h * s)), Image.LANCZOS)
        out = io.BytesIO()
        if img.get("mimeType") == "image/jpeg":
            im.convert("RGB").save(out, "JPEG", quality=90)
        else:
            im.save(out, "PNG", optimize=True)
        replaced[img["bufferView"]] = out.getvalue()
        print(f"  image {w}x{h} -> {im.size[0]}x{im.size[1]}")
    new_bin = b""
    for i, v in enumerate(views):
        chunk = replaced.get(i)
        if chunk is None:
            chunk = bin_[v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]
        new_bin = pad4(new_bin)
        v["byteOffset"] = len(new_bin)
        v["byteLength"] = len(chunk)
        new_bin += chunk
    new_bin = pad4(new_bin)
    js["buffers"][0]["byteLength"] = len(new_bin)
    js_bytes = pad4(json.dumps(js, separators=(",", ":")).encode(), b" ")
    total = 12 + 8 + len(js_bytes) + 8 + len(new_bin)
    with open(dst, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js_bytes), b"JSON") + js_bytes)
        f.write(struct.pack("<I4s", len(new_bin), b"BIN\x00") + new_bin)


if __name__ == "__main__":
    main()
