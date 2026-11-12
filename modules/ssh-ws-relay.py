#!/usr/bin/env python3
"""Small asyncio WebSocket-to-TCP relay for SSH-over-WS; standard library only."""
import argparse
import asyncio
import base64
import hashlib
import struct

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAX_FRAME = 1 << 20

async def read_frame(reader):
    head = await reader.readexactly(2)
    opcode = head[0] & 0x0F
    masked = bool(head[1] & 0x80)
    length = head[1] & 0x7F
    if length == 126:
        length = struct.unpack("!H", await reader.readexactly(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", await reader.readexactly(8))[0]
    if length > MAX_FRAME:
        raise ValueError("WebSocket frame too large")
    mask = await reader.readexactly(4) if masked else b""
    payload = await reader.readexactly(length)
    if masked:
        payload = bytes(value ^ mask[index & 3] for index, value in enumerate(payload))
    return opcode, payload

async def write_frame(writer, opcode, payload=b""):
    length = len(payload)
    head = bytes((0x80 | opcode, length)) if length < 126 else (
        bytes((0x80 | opcode, 126)) + struct.pack("!H", length) if length < 65536
        else bytes((0x80 | opcode, 127)) + struct.pack("!Q", length)
    )
    writer.write(head + payload)
    await writer.drain()

async def handle(reader, writer, target_host, target_port):
    tcp_writer = None
    try:
        request = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=10)
        if len(request) > 65536:
            raise ValueError("HTTP headers too large")
        lines = request.decode("latin1").split("\r\n")
        headers = {}
        for line in lines[1:]:
            if ":" in line:
                key, value = line.split(":", 1)
                headers[key.strip().lower()] = value.strip()
        key = headers.get("sec-websocket-key")
        if headers.get("upgrade", "").lower() != "websocket" or not key:
            writer.write(b"HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
            await writer.drain()
            return
        tcp_reader, tcp_writer = await asyncio.open_connection(target_host, target_port)
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode("ascii")).digest()).decode("ascii")
        writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + "\r\n\r\n").encode("ascii"))
        await writer.drain()

        async def websocket_to_tcp():
            while True:
                opcode, payload = await read_frame(reader)
                if opcode == 8:
                    return
                if opcode == 9:
                    await write_frame(writer, 10, payload)
                    continue
                if opcode in (0, 1, 2) and payload:
                    tcp_writer.write(payload)
                    await tcp_writer.drain()

        async def tcp_to_websocket():
            while True:
                data = await tcp_reader.read(16384)
                if not data:
                    return
                await write_frame(writer, 2, data)

        tasks = [asyncio.create_task(websocket_to_tcp()), asyncio.create_task(tcp_to_websocket())]
        done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        await asyncio.gather(*done, *pending, return_exceptions=True)
    except (asyncio.IncompleteReadError, ConnectionError, asyncio.TimeoutError, ValueError):
        pass
    finally:
        if tcp_writer is not None:
            tcp_writer.close()
            try:
                await tcp_writer.wait_closed()
            except Exception:
                pass
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=2082)
    parser.add_argument("--target", default="127.0.0.1")
    parser.add_argument("--target-port", type=int, default=109)
    args = parser.parse_args()
    server = await asyncio.start_server(lambda r, w: handle(r, w, args.target, args.target_port), args.listen, args.port)
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(main())
