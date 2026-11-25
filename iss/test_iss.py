#!/usr/bin/env python3
"""Self-test for the C ISS (run by `make iss-test`, after it is built).

usage: iss/test_iss.py BUILD_DIR      (default build)

1. The board demo prints its banner with thread 2's crc and echoes what it receives; the
   Python ISS (isa/iss.py) prints the same bytes.
2. Every Phase 3 kernel and the hazard test, built with the ISA 1.0 extensions (bench/,
   X = 7 rolled and 15 unrolled), leaves exactly the data memory that bench/kernels.py's
   reference interpreter expects. It takes 4 clocks per instruction of one copy, so the
   simulator counts cycles: the RTL benchmark harness reports 2 more (its pipeline fill).
"""
import os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path[:0] = [os.path.join(ROOT, "isa"), os.path.join(ROOT, "bench")]
from iss import Board, read_hex  # noqa: E402
import kernels  # noqa: E402


def iss(b, *args):
    r = subprocess.run([os.path.join(b, "iss", "slp-iss"), *args], capture_output=True)
    return r.returncode, r.stdout, r.stderr.decode()


def main():
    b = sys.argv[1] if len(sys.argv) > 1 else "build"
    b = os.path.join(ROOT, b) if not os.path.isabs(b) else b

    demo = os.path.join(b, "programs", "demo.hex")
    rc, out, _ = iss(b, "--clocks", "100000", "--rx", "ok!", demo)
    assert rc == 0 and out == b"sloputron-1 crc16=29B1\r\nok!", out
    py = Board(read_hex(demo))
    py.rx += b"ok!"
    py.run(100_000)
    assert bytes(py.tx) == out, (bytes(py.tx), out)

    stress = os.path.join(b, "programs", "stress.hex")
    rc, out, _ = iss(b, "--clocks", "300000", stress)
    py = Board(read_hex(stress))
    py.run(300_000)
    assert rc == 0 and out == bytes(py.tx) == b"S\r\n", (out, bytes(py.tx))

    n = 0
    for x in (7, 15):
        d = os.path.join(b, "bench", f"x{x}")
        for name, gen in kernels.TESTS.items():
            words = gen(x)
            mem = kernels.data_image(name, 4)
            per_copy = kernels.run(words, mem, 0, x)[0]
            rc, _, err = iss(b, "--flat", os.path.join(d, f"{name}_n4_data.hex"),
                             "--expect", os.path.join(d, f"{name}_n4_expect.hex"),
                             os.path.join(d, f"{name}.hex"))
            assert rc == 0, (x, name, err)
            clocks = int(err.split("slp-iss: ")[1].split()[0])
            assert clocks == 4 * per_copy, (x, name, clocks, per_copy)
            n += 1
    print(f"iss: demo and stress agree with the Python ISS; {n} kernel runs match the "
          "reference memory images and clock counts")


if __name__ == "__main__":
    main()
