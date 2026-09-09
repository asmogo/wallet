"""Local payment test services. Never expose this unauthenticated fixture publicly.

Each session has independent faults, request counters and relay storage. Proxies
forward real mint requests; faults never synthesize signatures or wallet balances.
"""
import asyncio
import base64
import cbor2
import hashlib
import json
import os
import secrets
import time
from contextlib import asynccontextmanager

import httpx
from bolt11 import Bolt11, MilliSatoshi, Tag, TagChar, Tags, encode, Feature, Features, FeatureState
from coincurve import PublicKeyXOnly
from fastapi import FastAPI, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse, Response, StreamingResponse

UPSTREAMS = {
    "nutshell": os.environ.get("NUTSHELL_MINT_URL", "http://127.0.0.1:3338"),
    "cdk": os.environ.get("CDK_MINT_URL", "http://127.0.0.1:3339"),
    "controlled": os.environ.get("CONTROLLED_MINT_URL", "http://127.0.0.1:3342"),
    "fees": os.environ.get("FEE_MINT_URL", "http://127.0.0.1:3343"),
}
sessions = {}


@asynccontextmanager
async def lifespan(app):
    async with httpx.AsyncClient(timeout=30, trust_env=False) as client:
        app.state.client = client
        yield


app = FastAPI(lifespan=lifespan)


def session(key):
    if key not in sessions:
        raise HTTPException(404, "Unknown scenario")
    return sessions[key]


def invoice(amount=21, description="Payment integration test", expiry=3600, age=0):
    tags = Tags([
        Tag(TagChar.payment_hash, secrets.token_hex(32)),
        Tag(TagChar.payment_secret, secrets.token_hex(32)),
        Tag(TagChar.features, Features.from_feature_list({Feature.payment_secret: FeatureState.supported, Feature.var_onion_optin: FeatureState.supported})),
        Tag(TagChar.description, description),
        Tag(TagChar.expire_time, expiry),
    ])
    value = Bolt11(currency="bc", date=int(time.time()) - age, tags=tags,
                   amount_msat=None if amount is None else MilliSatoshi(amount * 1000))
    return encode(value, private_key="0" * 63 + "1")


@app.get("/health")
async def health():
    return {"ready": True, "version": 1}


@app.post("/sessions")
async def create_session():
    key = secrets.token_hex(12)
    sessions[key] = {"faults": [], "requests": [], "deliveries": [], "events": {}, "sockets": {}}
    return {"id": key}


@app.delete("/sessions/{key}")
async def delete_session(key: str):
    state = session(key)
    for socket in list(state["sockets"]):
        await socket.close()
    sessions.pop(key, None)
    return {"deleted": True}


@app.get("/sessions/{key}")
async def inspect_session(key: str):
    state = session(key)
    return {name: state[name] for name in ("faults", "requests", "deliveries")}


@app.post("/sessions/{key}/faults")
async def add_fault(key: str, request: Request):
    fault = await request.json()
    if fault.get("action") not in ("reject", "lose_response", "delay"):
        raise HTTPException(400, "Unknown fault action")
    if fault.get("method") not in ("GET", "POST") or not fault.get("path", "").startswith("/v1/"):
        raise HTTPException(400, "Fault must identify a mint request")
    fault.setdefault("remaining", 1)
    session(key)["faults"].append(fault)
    return {"armed": True}


@app.post("/sessions/{key}/invoice")
async def create_invoice(key: str, request: Request):
    session(key)
    config = await request.json()
    return {"invoice": invoice(**config)}


@app.post("/sessions/{key}/pay/{mint}")
async def pay_controlled(key: str, mint: str, request: Request):
    session(key)
    if mint not in ("controlled", "fees"):
        raise HTTPException(400, "Not a controlled mint")
    response = await app.state.client.post(UPSTREAMS[mint] + "/test/pay", json=await request.json())
    return Response(response.content, status_code=response.status_code, media_type="application/json")


@app.post("/sessions/{key}/request")
async def cashu_request(key: str, request: Request):
    session(key)
    config = await request.json()
    payload = {"i": key, "u": config.get("unit", "sat"), "d": "Payment fixture",
               "t": [{"t": "post", "a": config["target"], "g": []}]}
    if config.get("amount") is not None:
        payload["a"] = config["amount"]
    if config.get("mints"):
        payload["m"] = config["mints"]
    return {"request": "creqA" + base64.urlsafe_b64encode(cbor2.dumps(payload)).decode().rstrip("=")}


@app.get("/sessions/{key}/received-token")
async def received_token(key: str):
    deliveries = session(key)["deliveries"]
    if not deliveries:
        raise HTTPException(404, "No payment delivered")
    payment = deliveries[-1]
    token = {"token": [{"mint": payment["mint"], "proofs": payment["proofs"]}], "unit": payment.get("unit", "sat")}
    return {"token": "cashuA" + base64.urlsafe_b64encode(json.dumps(token).encode()).decode().rstrip("="),
            "id": payment.get("id"), "count": len(deliveries)}


@app.post("/sessions/{key}/nwc")
async def nwc(key: str, request: Request):
    session(key)
    from nostr_client import nwc_request
    config = await request.json()
    try:
        return await nwc_request("ws://127.0.0.1:3341/sessions/" + key + "/relay", **config)
    except asyncio.TimeoutError:
        return JSONResponse({"timeout": True}, status_code=200)


@app.post("/sessions/{key}/receive")
async def receive_request(key: str, request: Request):
    payload = await request.json()
    session(key)["deliveries"].append(payload)
    return {}


@app.api_route("/sessions/{key}/mint/{mint}/{path:path}", methods=["GET", "POST"])
async def proxy(key: str, mint: str, path: str, request: Request):
    state = session(key)
    if mint not in UPSTREAMS or not path.startswith("v1/"):
        raise HTTPException(404)
    route = "/" + path
    fault = next((f for f in state["faults"] if f["remaining"] != 0
                  and f["method"] == request.method and route.startswith(f["path"])), None)
    if fault:
        fault["remaining"] -= 1
    record = {"method": request.method, "path": route, "forwarded": False,
              "fault": fault["action"] if fault else None}
    state["requests"].append(record)
    if fault and fault["action"] == "reject":
        return JSONResponse({"detail": "Scenario endpoint unavailable"}, status_code=503)
    if fault and fault["action"] == "delay":
        await asyncio.sleep(fault.get("seconds", 1))
    headers = {name: request.headers[name] for name in ("content-type", "prefer") if name in request.headers}
    upstream = await app.state.client.request(request.method, UPSTREAMS[mint] + route,
                                             params=request.query_params,
                                             content=await request.body(), headers=headers)
    record.update(forwarded=True, status=upstream.status_code)
    if fault and fault["action"] == "lose_response":
        # Upstream has completed. Break the response body, producing a transport
        # error instead of lying about the mint's committed state.
        async def broken_body():
            yield b""
            raise ConnectionResetError("Intentional lost payment response")
        return StreamingResponse(broken_body(), status_code=upstream.status_code,
                                 headers={"content-length": str(max(1, len(upstream.content)))})
    return Response(upstream.content, status_code=upstream.status_code,
                    media_type=upstream.headers.get("content-type", "application/json"))


def matches(event, filters):
    def one(f):
        return all((
            "kinds" not in f or event["kind"] in f["kinds"],
            "authors" not in f or event["pubkey"] in f["authors"],
            "ids" not in f or event["id"] in f["ids"],
            event["created_at"] >= f.get("since", 0),
            event["created_at"] <= f.get("until", float("inf")),
            all(any(t[0] == k[1:] and t[1] in values for t in event.get("tags", []) if len(t) >= 2)
                for k, values in f.items() if k.startswith("#")),
        ))
    return any(one(f) for f in filters)


@app.websocket("/sessions/{key}/relay")
async def relay(key: str, socket: WebSocket):
    state = session(key)
    await socket.accept()
    state["sockets"][socket] = {}
    try:
        while True:
            message = await socket.receive_json()
            if message[0] == "REQ":
                sub, filters = message[1], message[2:]
                state["sockets"][socket][sub] = filters
                for event in list(state["events"].values()):
                    if matches(event, filters):
                        await socket.send_json(["EVENT", sub, event])
                await socket.send_json(["EOSE", sub])
            elif message[0] == "CLOSE":
                state["sockets"][socket].pop(message[1], None)
            elif message[0] == "EVENT":
                event = message[1]
                # Validate both canonical content and Schnorr signature so
                # relay tests cannot succeed with unsigned synthetic events.
                canonical = [0, event["pubkey"], event["created_at"], event["kind"], event["tags"], event["content"]]
                digest = hashlib.sha256(json.dumps(canonical, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()
                try:
                    valid = digest == event["id"] and PublicKeyXOnly(bytes.fromhex(event["pubkey"])).verify(
                        bytes.fromhex(event["sig"]), bytes.fromhex(digest))
                except (ValueError, KeyError):
                    valid = False
                if not valid:
                    await socket.send_json(["OK", event["id"], False, "invalid: event signature or id"])
                    continue
                state["events"][event["id"]] = event
                await socket.send_json(["OK", event["id"], True, ""])
                for peer, subscriptions in list(state["sockets"].items()):
                    for sub, filters in list(subscriptions.items()):
                        if matches(event, filters):
                            await peer.send_json(["EVENT", sub, event])
    except WebSocketDisconnect:
        pass
    finally:
        state["sockets"].pop(socket, None)
