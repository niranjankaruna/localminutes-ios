"""Extract only the two validated CAB containers from the pinned Microsoft redistributable."""
from pathlib import Path
import struct
import sys


def main():
    source, destination = Path(sys.argv[1]), Path(sys.argv[2])
    data = source.read_bytes()
    destination.mkdir(parents=True, exist_ok=True)
    cursor = index = 0
    while (cursor := data.find(b"MSCF", cursor)) >= 0:
        if cursor + 36 > len(data):
            break
        size = struct.unpack_from("<I", data, cursor + 8)[0]
        if size < 36 or cursor + size > len(data) or data[cursor + 24:cursor + 26] != b"\x03\x01" or not struct.unpack_from("<H", data, cursor + 26)[0]:
            cursor += 4
            continue
        cabinet = data[cursor:cursor + size]
        position = struct.unpack_from("<I", cabinet, 16)[0]
        for _ in range(struct.unpack_from("<H", cabinet, 28)[0]):
            position += 16
            end = cabinet.find(b"\0", position)
            if end < position:
                raise ValueError("Invalid cabinet filename.")
            name = cabinet[position:end].decode("utf-8")
            if not name or any(char in name for char in "\\/:") or name in (".", ".."):
                raise ValueError("Unsafe cabinet path.")
            position = end + 1
        (destination / f"container-{index}.cab").write_bytes(cabinet)
        index += 1
        cursor += size
    if index != 2:
        raise ValueError("Unexpected pinned redistributable cabinet layout.")


if __name__ == "__main__":
    main()
