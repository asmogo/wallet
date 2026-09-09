"""A small signed NIP-47 client for testing the native wallet service locally."""
import asyncio
import base64
import hashlib
import json
import secrets
import time
from urllib.parse import parse_qs, urlparse

from coincurve import PrivateKey, PublicKey
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
import websockets


def encode_event(secret, kind, tags, content):
    key = PrivateKey(bytes.fromhex(secret))
    event = dict(pubkey=key.public_key.format()[1:].hex(), created_at=int(time.time()),
                 kind=kind, tags=tags, content=content)
    canonical = [0, event['pubkey'], event['created_at'], kind, tags, content]
    digest = hashlib.sha256(json.dumps(canonical, separators=(',', ':'), ensure_ascii=False).encode()).digest()
    event.update(id=digest.hex(), sig=key.sign_schnorr(digest).hex())
    return event


def shared_key(secret, pubkey):
    return PublicKey(bytes.fromhex('02' + pubkey)).multiply(bytes.fromhex(secret)).format(compressed=False)[1:33]


def encrypt(secret, pubkey, value):
    iv = secrets.token_bytes(16)
    padder = padding.PKCS7(128).padder()
    data = padder.update(json.dumps(value).encode()) + padder.finalize()
    cipher = Cipher(algorithms.AES(shared_key(secret, pubkey)), modes.CBC(iv)).encryptor()
    return base64.b64encode(cipher.update(data) + cipher.finalize()).decode() + '?iv=' + base64.b64encode(iv).decode()


def decrypt(secret, pubkey, value):
    ciphertext, iv = value.split('?iv=')
    cipher = Cipher(algorithms.AES(shared_key(secret, pubkey)), modes.CBC(base64.b64decode(iv))).decryptor()
    data = cipher.update(base64.b64decode(ciphertext)) + cipher.finalize()
    unpadder = padding.PKCS7(128).unpadder()
    return json.loads(unpadder.update(data) + unpadder.finalize())


async def nwc_request(relay, uri, method, params=None, duplicate=False):
    parsed = urlparse(uri)
    secret = parse_qs(parsed.query)['secret'][0]
    pubkey = parsed.netloc
    request = {'method': method, 'params': params or {}}
    event = encode_event(secret, 23194, [['p', pubkey]], encrypt(secret, pubkey, request))
    async with websockets.connect(relay) as ws:
        await ws.send(json.dumps(['REQ', 'response', {'kinds': [23195], '#e': [event['id']]}]))
        # Wait for subscription readiness so a fast service cannot beat REQ.
        while json.loads(await asyncio.wait_for(ws.recv(), 10))[0] != 'EOSE':
            pass
        await ws.send(json.dumps(['EVENT', event]))
        if duplicate:
            await ws.send(json.dumps(['EVENT', event]))
        async def response():
            while True:
                message = json.loads(await ws.recv())
                if message[0] == 'EVENT' and message[2]['pubkey'] == pubkey:
                    return decrypt(secret, pubkey, message[2]['content'])
        return await asyncio.wait_for(response(), 12)
