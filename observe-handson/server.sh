#!/bin/bash
# ════════════════════════════════════════════════════════════════
#   TLS Discord Theater  ——  🖥️  SERVER ROLE
#   Usage: bash server.sh
#   Deps:  openssl, xxd
# ════════════════════════════════════════════════════════════════

# ── 色 ─────────────────────────────────────────────────────────
BLD='\033[1m' DIM='\033[2m' RST='\033[0m'
GRN='\033[0;32m' YLW='\033[1;33m' CYN='\033[0;36m'
RED='\033[0;31m' MGN='\033[0;35m' WHT='\033[1;37m'

ok()  { echo -e "  ${GRN}✓${RST} $1"; }
ng()  { echo -e "  ${RED}✗ $1${RST}" >&2; exit 1; }
h()   { echo -e "\n${YLW}${BLD}  ╔══ $1${RST}"; }
cont(){ echo -e "\n  ${DIM}[Enter] で続行...${RST}"; read -r; }

# base64 decode — macOS / Linux 両対応
b64d() { base64 -d 2>/dev/null || base64 -D; }
b64e() { base64 | tr -d '\n'; }

# ── TLS 1.2 PRF (HMAC-SHA256) ───────────────────────────────────
_hmac() { # <key_hex> <data_hex> → hex
  printf '%s' "$2" | xxd -r -p | \
    openssl dgst -sha256 -mac HMAC -macopt "hexkey:$1" -binary 2>/dev/null | \
    xxd -p | tr -d '\n'
}
prf() { # <secret_hex> <label> <seed_hex> <len_bytes> → hex
  local S="$1" LBL="$2" SEED="$3" N="$4"
  local LH; LH=$(printf '%s' "$LBL" | xxd -p | tr -d '\n')
  local A0="${LH}${SEED}" A="${LH}${SEED}" OUT=""
  while [ "${#OUT}" -lt $(( N*2 )) ]; do
    A=$(_hmac "$S" "$A")
    OUT="${OUT}$(_hmac "$S" "${A}${A0}")"
  done
  printf '%s' "${OUT:0:$(( N*2 ))}"
}

# ── Discord 投稿フォーマット ────────────────────────────────────
post() {
  echo ""
  echo -e "${YLW}  ┌────────────────────────────────────────────────────┐"
  echo -e "  │  📢  以下をそのままDiscordにコピペしてください      │"
  echo -e "  └────────────────────────────────────────────────────┘${RST}"
  echo ""
  echo -e "$1"
  echo ""
  cont
}

ask() { # <prompt>  → sets $_IN
  echo -e "\n  ${CYN}⌨️  $1${RST}"
  echo -e "  ${DIM}Discordの投稿からコピペしてください${RST}"
  printf '  > '; read -r _IN
  _IN=$(printf '%s' "$_IN" | tr -d ' \r\n')
}

# ── プリフライト ────────────────────────────────────────────────
command -v openssl >/dev/null || ng "openssl が見つかりません"
command -v xxd     >/dev/null || ng "xxd が見つかりません"

WD="tls-theater-server"
mkdir -p "$WD"

# ── バナー ──────────────────────────────────────────────────────
clear
echo -e "${YLW}${BLD}"
cat << 'BANNER'

  ╔══════════════════════════════════════════════════════╗
  ║   TLS Discord Theater  —  🖥️  サーバー役             ║
  ║   指示通りにDiscordへ投稿してください                 ║
  ╚══════════════════════════════════════════════════════╝

BANNER
echo -e "${RST}"
echo -e "  ${DIM}このスクリプトは対話式です。各ステップで${RST}"
echo -e "  ${DIM}Discordに投稿するテキストが表示されます。${RST}"
cont

# ════════════════════════════════════════════════════════════════
#  STEP 1  CA・証明書・鍵ペア生成
# ════════════════════════════════════════════════════════════════
h "STEP 1  鍵ペア・証明書を生成"

openssl genrsa -out "$WD/ca.key"     2048 2>/dev/null
openssl req -new -x509 -days 1 -key "$WD/ca.key" -out "$WD/ca.crt" \
  -subj "/CN=TheaterCA" 2>/dev/null
openssl genrsa -out "$WD/server.key" 2048 2>/dev/null
openssl req -new -key "$WD/server.key" -out "$WD/server.csr" \
  -subj "/CN=TLSTheater-Server" 2>/dev/null
openssl x509 -req -days 1 \
  -in "$WD/server.csr" -CA "$WD/ca.crt" -CAkey "$WD/ca.key" \
  -CAcreateserial -out "$WD/server.crt" 2>/dev/null
openssl x509 -in "$WD/server.crt" -pubkey -noout \
  > "$WD/server_pubkey.pem" 2>/dev/null

PUBKEY=$(cat "$WD/server_pubkey.pem")
FP=$(openssl x509 -in "$WD/server.crt" -fingerprint -sha256 -noout \
     2>/dev/null | cut -d= -f2)

ok "鍵ペア・証明書 生成完了"
ok "Fingerprint: $FP"

post "\`\`\`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖥️ SERVER ▸ Certificate + ServerHello [Step 1/5]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
サーバー公開鍵です。誰でも暗号化に使えます。
でも復号できるのは私だけです 🔐

${PUBKEY}
Fingerprint: ${FP}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
\`\`\`"

# ════════════════════════════════════════════════════════════════
#  STEP 2  ClientRandom 受信  →  ServerRandom 生成・投稿
# ════════════════════════════════════════════════════════════════
h "STEP 2  乱数の交換"

ask "ClientRandom（クライアントが投稿したhex 64文字）:"
CR="$_IN"
echo "$CR" > "$WD/client_random.txt"
ok "ClientRandom 受信: ${CR:0:20}..."

SR=$(openssl rand -hex 32)
echo "$SR" > "$WD/server_random.txt"
ok "ServerRandom 生成: ${SR:0:20}..."

post "\`\`\`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖥️ SERVER ▸ ServerRandom [Step 2/5]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${SR}

この乱数は全員が見えています。
でもこれだけでは何も解読できません。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
\`\`\`"

# ════════════════════════════════════════════════════════════════
#  STEP 3  EncryptedPMS 受信・復号
# ════════════════════════════════════════════════════════════════
h "STEP 3  ClientKeyExchange (暗号化PMS) を受け取る"

ask "暗号化PMS（base64 一行）:"
ENC_B64="$_IN"
printf '%s' "$ENC_B64" | b64d > "$WD/enc_pms.bin" 2>/dev/null \
  || ng "base64デコード失敗。貼り付け内容を確認してください"

openssl pkeyutl -decrypt \
  -inkey "$WD/server.key" \
  -in    "$WD/enc_pms.bin" \
  -out   "$WD/pms.bin" 2>/dev/null \
  || ng "PMS復号失敗。base64の貼り付けを確認してください"

PMS=$(xxd -p "$WD/pms.bin" | tr -d '\n')
ok "PMS 復号成功！"
ok "先頭2バイト (TLS version): ${PMS:0:4}  ← 0303 = TLS 1.2 であることを確認"
echo ""
echo -e "  ${MGN}👁  観客には暗号文しか見えないので PMS は分かりません${RST}"
cont

# ════════════════════════════════════════════════════════════════
#  STEP 4  鍵導出（自動）
# ════════════════════════════════════════════════════════════════
h "STEP 4  Master Secret & Session Keys 導出"

printf '  PRF計算中 (Master Secret) ...'
MS=$(prf "$PMS" "master secret" "${CR}${SR}" 48)
echo " done"
echo "$MS" > "$WD/master_secret.txt"

printf '  PRF計算中 (Key Expansion)  ...'
KM=$(prf "$MS" "key expansion" "${SR}${CR}" 128)
echo " done"

CW_MAC="${KM:0:64}";   SW_MAC="${KM:64:64}"
CW_KEY="${KM:128:32}"; SW_KEY="${KM:160:32}"
CW_IV="${KM:192:32}";  SW_IV="${KM:224:32}"

{ echo "MS=$MS"
  echo "CW_MAC=$CW_MAC"; echo "SW_MAC=$SW_MAC"
  echo "CW_KEY=$CW_KEY"; echo "SW_KEY=$SW_KEY"
  echo "CW_IV=$CW_IV";   echo "SW_IV=$SW_IV"
} > "$WD/session_keys.txt"

ok "Master Secret   : ${MS:0:24}..."
ok "Client Write Key: $CW_KEY"
ok "Client Write IV : $CW_IV"
echo ""
echo -e "  ${YLW}💬 MC: 「今この瞬間、サーバーとクライアントは"
echo -e "         誰にも知られずに同じ鍵を共有しました」${RST}"
cont

# ════════════════════════════════════════════════════════════════
#  STEP 5  暗号文受信・復号・MAC検証・投稿
# ════════════════════════════════════════════════════════════════
h "STEP 5  暗号文を受け取って復号する"

ask "暗号文（base64 一行）:"
CT_B64="$_IN"
printf '%s' "$CT_B64" | b64d > "$WD/ciphertext.bin" 2>/dev/null \
  || ng "base64デコード失敗"

openssl enc -d -aes-128-cbc \
  -K "$CW_KEY" -iv "$CW_IV" \
  -in  "$WD/ciphertext.bin" \
  -out "$WD/dec_withmac.bin" 2>/dev/null \
  || ng "AES復号失敗 — 鍵が一致していません"

TOTAL=$(wc -c < "$WD/dec_withmac.bin")
MLEN=$(( TOTAL - 32 ))
dd if="$WD/dec_withmac.bin" bs=1 count=$MLEN  of="$WD/recv_msg.bin" 2>/dev/null
dd if="$WD/dec_withmac.bin" bs=1 skip=$MLEN   of="$WD/recv_mac.bin" 2>/dev/null

MSG=$(cat "$WD/recv_msg.bin")
DHEX=$(xxd -p "$WD/recv_msg.bin" | tr -d '\n')
SEQ="0000000000000000"
CALC_MAC=$(_hmac "$CW_MAC" "${SEQ}${DHEX}")
RECV_MAC=$(xxd -p "$WD/recv_mac.bin" | tr -d '\n')

echo ""
if [ "$CALC_MAC" = "$RECV_MAC" ]; then
  echo -e "  ${GRN}${BLD}✓ MAC検証 成功！改ざんなし${RST}"
  echo -e "  ${GRN}${BLD}📨 受信メッセージ: \"$MSG\"${RST}"

  post "\`\`\`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖥️ SERVER ▸ 復号完了 🎉 [Step 5/5]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ MAC検証: 成功（改ざんなし）
📨 受信メッセージ:

   「${MSG}」

みなさん全パケットを見ていましたよね？
復号できましたか？ 😏
server.key がなければ無理です。これがTLS。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
\`\`\`"
else
  echo -e "  ${RED}✗ MAC不一致！${RST}"
  echo -e "  計算値: $CALC_MAC"
  echo -e "  受信値: $RECV_MAC"
  ng "MAC検証失敗 — 鍵のズレか改ざんの可能性"
fi

# ── 完了 ──────────────────────────────────────────────────────
echo ""
echo -e "${YLW}${BLD}  ══ ハンドシェイク完了！ ══${RST}"
echo ""
echo -e "  生成ファイル:"
ls -1 "$WD/" | while read -r f; do echo -e "    ${DIM}$f${RST}"; done
echo ""
echo -e "  ${CYN}ヒント: $WD/session_keys.txt をクライアント役と照合すると"
echo -e "  同じ鍵が導出されていることを確認できます${RST}"
