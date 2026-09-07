#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PAYMENT_TEST_PYTHON:-${SCRIPT_DIR}/.nutshell-venv/bin/python}"
WORK_DIR="${SCRIPT_DIR}/.payment-workdir"
mkdir -p "$WORK_DIR"
if [ -e "$WORK_DIR/pids" ]; then
    echo 'Payment fixtures already have a PID ledger; stop them before starting again.' >&2
    exit 1
fi
: > "$WORK_DIR/pids"
trap '"${SCRIPT_DIR}/stop-payment-fixtures.sh"' ERR
for profile in controlled fees; do
    port=3342
    input_fee=0
    if [ "$profile" = fees ]; then port=3343; input_fee=1000; fi
    mkdir -p "$WORK_DIR/$profile"
    # Empty local dotenv and CASHU_DIR prevent inherited personal mint settings.
    : > "$WORK_DIR/$profile/.env"
    (
        cd "$WORK_DIR/$profile"
        exec nohup env PYTHONPATH="${SCRIPT_DIR}/payment-tests" \
            CASHU_DIR="$WORK_DIR/$profile" MINT_DATABASE="$WORK_DIR/$profile" \
            MINT_URL="http://127.0.0.1:$port" MINT_LISTEN_HOST=127.0.0.1 MINT_LISTEN_PORT="$port" \
            MINT_BACKEND_BOLT11_SAT=ControlledFakeWallet \
            MINT_PRIVATE_KEY="PAYMENT_TEST_${profile}_DO_NOT_USE" \
            MINT_INPUT_FEE_PPK="$input_fee" FAKEWALLET_BRR=false \
            MINT_QUOTE_BACKEND_CHECK_RATE_LIMIT=0 MINT_RATE_LIMIT=false \
            "$PYTHON_BIN" -m uvicorn controlled_mint:app --host 127.0.0.1 --port "$port" --log-level warning
    ) > "$WORK_DIR/$profile.log" 2>&1 < /dev/null &
    echo "$!" >> "$WORK_DIR/pids"
done
nohup env PYTHONPATH="${SCRIPT_DIR}/payment-tests" "$PYTHON_BIN" -m uvicorn server:app \
    --host 127.0.0.1 --port 3341 --log-level warning \
    > "$WORK_DIR/server.log" 2>&1 < /dev/null &
echo "$!" >> "$WORK_DIR/pids"
for endpoint in '3341/health' '3342/v1/info' '3343/v1/info'; do
    ready=false
    for _ in {1..100}; do
        if curl -fsS "http://127.0.0.1:$endpoint" > /dev/null 2>&1; then ready=true; break; fi
        sleep 0.2
    done
    if [ "$ready" != true ]; then echo "Payment fixture failed readiness: $endpoint" >&2; exit 1; fi
done
trap - ERR
echo 'Payment fixtures ready.'
