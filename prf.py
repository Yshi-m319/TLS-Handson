#!/usr/bin/env python3
"""
TLS 1.2 PRF (P_SHA256) + Finished verify_data ユーティリティ

■ 鍵導出（セッション開始時）
  python3 prf.py <pms_hex> <client_random_hex> <server_random_hex>

■ Finished verify_data の生成（ChangeCipherSpec 後）
  python3 prf.py finished <master_secret_hex> <hs_hash_hex> client
  python3 prf.py finished <master_secret_hex> <hs_hash_hex> server

hs_hash は以下で作る:
  cat <(echo -n $CLIENT_RANDOM | xxd -r -p) \\
      <(echo -n $SERVER_RANDOM | xxd -r -p) \\
      enc_pms.bin > hs_log.bin
  HS_HASH=$(openssl dgst -sha256 -hex hs_log.bin | cut -d' ' -f2)
"""

import hmac
import hashlib
import sys


def p_sha256(secret: bytes, seed: bytes, length: int) -> bytes:
    a = seed
    out = b""
    while len(out) < length:
        a = hmac.new(secret, a, hashlib.sha256).digest()
        out += hmac.new(secret, a + seed, hashlib.sha256).digest()
    return out[:length]


def prf(secret: bytes, label: str, seed: bytes, length: int) -> bytes:
    return p_sha256(secret, label.encode() + seed, length)


def key_expansion(pms_hex: str, cr_hex: str, sr_hex: str) -> None:
    pms = bytes.fromhex(pms_hex)
    cr = bytes.fromhex(cr_hex)
    sr = bytes.fromhex(sr_hex)

    ms = prf(pms, "master secret", cr + sr, 48)
    km = prf(ms, "key expansion", sr + cr, 128)

    print(f"master_secret    = {ms.hex()}")
    print(f"client_write_MAC = {km[0:32].hex()}")
    print(f"server_write_MAC = {km[32:64].hex()}")
    print(f"client_write_key = {km[64:80].hex()}")
    print(f"server_write_key = {km[80:96].hex()}")
    print(f"client_write_iv  = {km[96:112].hex()}")
    print(f"server_write_iv  = {km[112:128].hex()}")


def finished(ms_hex: str, hs_hash_hex: str, role: str) -> None:
    ms = bytes.fromhex(ms_hex)
    hs_hash = bytes.fromhex(hs_hash_hex)
    label = f"{role} finished"  # "client finished" or "server finished"
    vd = prf(ms, label, hs_hash, 12)
    print(vd.hex())


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "finished":
        if len(sys.argv) != 5:
            print(
                "使い方: python3 prf.py finished <ms_hex> <hs_hash_hex> <client|server>",
                file=sys.stderr,
            )
            sys.exit(1)
        finished(sys.argv[2], sys.argv[3], sys.argv[4])
    elif len(sys.argv) == 4:
        key_expansion(sys.argv[1], sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
        sys.exit(1)
