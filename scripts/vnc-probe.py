#!/usr/bin/env python3
"""Minimal RFB client: optionally send a tap, then save one framebuffer update as PNG."""
import socket, struct, sys, zlib, time
host, port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
tap = tuple(map(int, sys.argv[4].split(","))) if len(sys.argv) > 4 else None
s = socket.create_connection((host, port), timeout=120)
def rd(n):
    b = b""
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c: raise EOFError
        b += c
    return b
ver = rd(12); s.sendall(ver)
types = rd(rd(1)[0]); print("version", ver.strip().decode(), "security", list(types))
if 1 not in types: sys.exit("server requires authentication")
s.sendall(b"\x01"); assert struct.unpack(">I", rd(4))[0] == 0
s.sendall(b"\x01")
w, h = struct.unpack(">HH", rd(4)); rd(16); name = rd(struct.unpack(">I", rd(4))[0])
print("framebuffer", w, h, name.decode(errors="replace"))
s.sendall(struct.pack(">BxxxBBBBHHHBBBxxx", 0, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))
s.sendall(struct.pack(">BxHi", 2, 1, 0))
if tap:
    s.sendall(struct.pack(">BBHH", 5, 1, *tap)); time.sleep(0.15); s.sendall(struct.pack(">BBHH", 5, 0, *tap)); print("tap sent", tap)
s.sendall(struct.pack(">BBHHHH", 3, 0, 0, 0, w, h))
fb = bytearray(w * h * 4); t = time.time()
while True:
    if rd(1)[0] != 0: continue
    rd(1); n = struct.unpack(">H", rd(2))[0]
    for _ in range(n):
        x, y, rw, rh, enc = struct.unpack(">HHHHi", rd(12)); assert enc == 0
        data = rd(rw * rh * 4)
        for row in range(rh):
            o = (y + row) * w * 4 + x * 4
            fb[o:o + rw * 4] = data[row * rw * 4:(row + 1) * rw * 4]
    break
print("frame in %.1fs" % (time.time() - t))
raw = bytearray()
for row in range(h):
    px = fb[row * w * 4:(row + 1) * w * 4]; line = bytearray(w * 3)
    line[0::3] = px[2::4]; line[1::3] = px[1::4]; line[2::3] = px[0::4]
    raw += b"\0" + line
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
open(out, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
print("saved", out, "distinct-pixel-sample", len({bytes(fb[i:i+3]) for i in range(0, len(fb), 4*97)}))
