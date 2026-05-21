#!/bin/bash
# ════════════════════════════════════════════════════════════════
#   TLS Discord Theater  ——  💻 CLIENT ROLE
#   Usage: bash client.sh
#   Deps:  openssl, xxd
# ════════════════════════════════════════════════════════════════

# ── 色 ─────────────────────────────────────────────────────────
BLD='\033[1m' DIM='\033[2m' RST='\033[0m'
GRN='\033[0;32m' YLW='\033[1;33m' CYN='\033[0;36m'
RED='\033[0;31m' MGN='\033[0;35m' BLU='\033[0;34m'

ok()  { echo -e "  ${GRN}✓${RST} $1"; }
ng()  { echo -e "  ${RED}✗ $1${RST}" >&2; exit 1; }
h()   { echo -e "\n${BLU}${BLD}  ╔══ $1${RST}"; }
cont(){ echo -e "\n  ${DIM}[Enter] で続行...${RST}"; read -r; }

b64d() { base64 -d 2>/dev/null || base64 -D; }
b64e() { base64 | tr -d '\n'; }

# ── TLS 1.2 PRF (HMAC-SHA256) ───────────────────────────────────
_hmac() {
  printf '%s' "$2" | xxd -r -p | \
    openssl dgst -sha256 -mac HMAC -macopt "hexkey:$1" -binary 2>/dev/null | \
    xxd -p | tr -d '\n'
}
prf() {
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
  echo -e "${BLU}  ┌────────────────────────────────────────────────────┐"
  echo -e "  │  📢  以下をそのままDiscordにコピペしてください      │"
  echo -e "  └────────────────────────────────────────────────────┘${RST}"
  echo ""
  echo -e "$1"
  echo ""
  cont
}

ask() {
  echo -e "\n  ${CYN}⌨️  $1${RST}"
  echo -e "  ${DIM}Discordの投稿からコピペしてください${RST}"
  printf '  > '; read -r _IN
  _IN=$(printf '%s' "$_IN" | tr -d ' \r\n')
}

# ── プリフライト ────────────────────────────────────────────────
command -v openssl >/dev/null || ng "openssl が見つかりません"
command -v xxd     >/dev/null || ng "xxd が見つかりません"

WD="tls-theater-client"
mkdir -p "$WD"

# ── バナー ──────────────────────────────────────────────────────
clear
echo -e "${BLU}${BLD}"
cat << 'BANNER'

  ╔══════════════════════════════════════════════════════╗
  ║   TLS Discord Theater  —  💻 クライアント役          ║
  ║   指示通りにDiscordへ投稿してください                 ║
  ╚══════════════════════════════════════════════════════╝

BANNER
echo -e "${RST}"
echo -e "  ${DIM}このスクリプトは対話式です。各ステップで${RST}"
echo -e "  ${DIM}Discordに投稿するテキストが表示されます。${RST}"
cont

# ════════════════════════════════════════════════════════════════
#  STEP 1  ClientRandom 生成・投稿
# ════════════════════════════════════════════════════════════════
h "STEP 1  ClientRandom を生成して投稿"

CR=$(openssl rand -hex 32)
echo "$CR" > "$WD/client_random.txt"
ok "ClientRandom: $CR"

post "\`\`\`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💻 CLIENT ▸ ClientHello — Random [Step 1/5]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${CR}

ただの乱数です。でも後でとても重要になります👀
観客のみなさん: この値、メモしておいてください
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
\`\`\`"

# ════════════════════════════════════════════════════════════════
#  STEP 2  公開鍵・ServerRandom を受け取る
# ════════════════════════════════════════════════════════════════
h "STEP 2  サーバーの公開鍵と ServerRandom を受け取る"

echo -e "\n  ${CYN}⌨️  サーバーが投稿した公開鍵を貼ってください${RST}"
echo -e "  ${DIM}（-----BEGIN PUBLIC KEY----- から"
echo -e "   -----END PUBLIC KEY----- まで全部貼って Enter × 2）${RST}"
echo ""
PUBKEY=""
while IFS= read -r line; do
  PUBKEY="${PUBKEY}${line}"$'\n'
  [[ "$line" == "-----END PUBLIC KEY-----" ]] && break
done
printf '%s' "$PUBKEY" > "$WD/server_pubkey.pem"
ok "公開鍵 受信・保存完了"

# 証明書フィンガープリント表示（あれば）
ask "ServerRandom（サーバーが投稿したhex 64文字）:"
SR="$_IN"
echo "$SR" > "$WD/server_random.txt"
ok "ServerRandom 受信: ${SR:0:20}..."

# ════════════════════════════════════════════════════════════════
#  STEP 3  PMS 生成・暗号化・投稿
# ════════════════════════════════════════════════════════════════
h "STEP 3  Pre-Master Secret を生成して暗号化"

# 48バイト: 先頭2バイト=TLS1.2バージョン(0303) + 46バイト乱数
PMS_RAND=$(openssl rand -hex 46)
PMS="0303${PMS_RAND}"
printf '%s' "$PMS" | xxd -r -p > "$WD/pms.bin"
ok "PMS 生成: ${PMS:0:8}...  ← 先頭 0303 = TLS 1.2"

openssl pkeyutl -encrypt \
  -inkey "$WD/server_pubkey.pem" -pubin \
  -in    "$WD/pms.bin" \
  -out   "$WD/enc_pms.bin" 2>/dev/null \
  || ng "暗号化失敗 — 公開鍵の貼り付けを確認してください"

ENC_B64=$(b64e < "$WD/enc_pms.bin")
ok "暗号化完了 （${#ENC_B64} 文字のbase64 / RSA 2048 = 256バイト）"

post "\`\`\`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💻 CLIENT ▸ ClientKeyExchange [Step 3/5]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
サーバー公開鍵で暗号化したPMS（48バイト）
server.key がなければ復号不可能 🔒

${ENC_B64}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
\`\`\`"

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
echo -e "  ${MGN}サーバーも今全く同じ値を計算しています。"
echo -e "  でも観客には分かりません──enc_pms.bin を復号する"
echo -e "  には server.key が必要だからです。${RST}"
cont

# ════════════════════════════════════════════════════════════════
#  STEP 5  メッセージを入力・暗号化・投稿
# ════════════════════════════════════════════════════════════════
h "STEP 5  メッセージを暗号化して送信"

echo -e "\n  ${CYN}⌨️  サーバーへ送るメッセージを入力してください:${RST}"
printf '  > '; read -r PLAINTEXT
printf '%s' "$PLAINTEXT" > "$WD/plaintext.txt"

# MAC = HMAC-SHA256(CW_MAC, SeqNum || PlainText)
SEQ="0000000000000000"
DHEX=$(xxd -p "$WD/plaintext.txt" | tr -d '\n')
MAC=$(_hmac "$CW_MAC" "${SEQ}${DHEX}")
ok "MAC計算: ${MAC:0:20}..."

# 平文 + MAC をバイナリに
{ cat "$WD/plaintext.txt"
  printf '%s' "$MAC" | xxd -r -p
} > "$WD/ptxt_withmac.bin"

# AES-128-CBC 暗号化
openssl enc -aes-128-cbc \
  -K "$CW_KEY" -iv "$CW_IV" \
  -in  "$WD/ptxt_withmac.bin" \
  -out "$WD/ciphertext.bin" 2>/dev/null \
  || ng "暗号化失敗"

CT_B64=$(b64e < "$WD/ciphertext.bin")
ok "暗号化完了 → ${#CT_B64} 文字のbase64"

post "\`\`\`
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💻 CLIENT ▸ Application Data（暗号文）[Step 5/5]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AES-128-CBC + HMAC-SHA256 で保護済み
セッション鍵を知らない人には解読不能です 🔒

${CT_B64}

観客の方へ: 全データを持っていますよね？
さあ、復号してみてください 😈
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
\`\`\`"

# ── 盗聴チャレンジ用データを保存 ──────────────────────────────
{
  echo "CLIENT_RANDOM=$CR"
  echo "SERVER_RANDOM=$SR"
  echo "ENC_PMS_B64=$ENC_B64"
  echo "CIPHERTEXT_B64=$CT_B64"
} > "$WD/challenge_data.txt"

echo ""
echo -e "  ${YLW}💡 observer.html に challenge_data.txt の値を入力すると"
echo -e "     観客が「盗聴チャレンジ」を体験できます！${RST}"

echo ""
echo -e "${BLU}${BLD}  ══ クライアント側完了！サーバーの復号を待ちましょう ══${RST}"
echo ""
echo -e "  生成ファイル:"
ls -1 "$WD/" | while read -r f; do echo -e "    ${DIM}$f${RST}"; done
