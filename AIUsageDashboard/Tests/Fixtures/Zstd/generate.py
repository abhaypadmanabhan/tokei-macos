"""Rebuild small synthetic fixtures with the installed zstd; never reads real logs."""
from pathlib import Path
import random
import subprocess

root = Path(__file__).parent

def compress(name, data, *options):
    result = subprocess.run(["zstd", "-q", "-c", *options], input=data, check=True, capture_output=True).stdout
    assert len(result) <= 16 * 1024
    (root / (name + ".zst")).write_bytes(result)
    return result

rng = random.Random(71)
raw = bytes(rng.randrange(256) for _ in range(1024))
(root / "raw.bin").write_bytes(raw)
compress("raw", raw, "--no-check")
compress("rle", b"R" * 300000, "--no-check")
text = b"".join(f'{{"index":{i % 97},"message":"the quick brown fox visits a quiet room","tokens":{i % 37}}}\n'.encode() for i in range(5000))
compressed = compress("compressed", text, "-3", "--no-check")
compress("stress", text[:2048], "-3", "--check")
compress("window", text[:50000], "-3", "--no-content-size", "--zstd=wlog=10")
# Unknown-size 128 KiB window, 2048 full RLE blocks (256 MiB) plus one extra.
header = bytes.fromhex("28b52ffd0038")
rle_block = ((128 * 1024 << 3) | 2).to_bytes(3, "little") + b"R"
last = ((128 * 1024 << 3) | 3).to_bytes(3, "little") + b"R"
(root / "output-limit.zst").write_bytes(header + rle_block * 2048 + last)
(root / "multi-output-limit.zst").write_bytes(header + rle_block * 2047 + last + compress("limit-tail", b"x", "--check"))
compress("checksum", text, "-9", "--check")
compress("high", text, "-19", "--check")
(root / "multi.zst").write_bytes(compressed + compress("tail", b"tail\n", "--check"))
(root / "truncated.zst").write_bytes(compressed[:-1])
for offset in (0, 4, 9, len(compressed) // 2, len(compressed) - 1):
    damaged = bytearray((root / "checksum.zst").read_bytes())
    damaged[min(offset, len(damaged) - 1)] ^= 0x80
    (root / f"corrupt-{offset}.zst").write_bytes(damaged)
# A legal non-single-segment header advertising a 256 MiB window (over our cap).
(root / "oversized-window.zst").write_bytes(bytes.fromhex("28b52ffd0090010000"))
print({p.name: p.stat().st_size for p in sorted(root.glob("*.zst"))})
