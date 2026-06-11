#!/usr/bin/env python3
"""Check unclaimed ARM redeem requests with Multicall3.

Defaults to the Ethereum stETH ARM. The script intentionally uses only the
Python standard library so it can run in this repository without installing
extra packages.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


DEFAULT_ARM = "0x85B78AcA6Deae198fBF201c82DAF6Ca21942acc6"
MULTICALL3 = "0xcA11bde05977b3631167028862bE2a173976CA11"

SELECTOR_AGGREGATE3 = bytes.fromhex("82ad56cb")
SELECTOR_NEXT_WITHDRAWAL_INDEX = bytes.fromhex("bba9282e")
SELECTOR_WITHDRAWAL_REQUESTS = bytes.fromhex("937b2581")
SELECTOR_CLAIMABLE = bytes.fromhex("af38d757")
SELECTOR_CLAIM_DELAY = bytes.fromhex("1c8ec299")


@dataclass(frozen=True)
class WithdrawalRequest:
    request_id: int
    withdrawer: str
    claimed: bool
    claim_timestamp: int
    assets: int
    queued: int
    shares: int | None
    queue_units: str


@dataclass(frozen=True)
class Snapshot:
    block_number: int
    block_timestamp: int
    next_withdrawal_index: int
    claimable_frontier: int
    claim_delay: int


def load_dotenv(path: Path) -> None:
    if not path.exists():
        return

    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'\"")
        if key and key not in os.environ:
            os.environ[key] = value


def strip_0x(value: str) -> str:
    return value[2:] if value.startswith("0x") else value


def validate_address(address: str) -> str:
    raw = strip_0x(address).lower()
    if len(raw) != 40:
        raise ValueError(f"invalid address length: {address}")
    int(raw, 16)
    return "0x" + raw


def pad32(data: bytes) -> bytes:
    padding = (-len(data)) % 32
    return data + (b"\x00" * padding)


def word(value: int | bool) -> bytes:
    return int(value).to_bytes(32, byteorder="big")


def address_word(address: str) -> bytes:
    return b"\x00" * 12 + bytes.fromhex(strip_0x(validate_address(address)))


def encode_bytes(data: bytes) -> bytes:
    return word(len(data)) + pad32(data)


def encode_call3(target: str, allow_failure: bool, call_data: bytes) -> bytes:
    return (
        address_word(target)
        + word(allow_failure)
        + word(96)
        + encode_bytes(call_data)
    )


def encode_aggregate3(calls: Iterable[tuple[str, bool, bytes]]) -> str:
    encoded_calls = [
        encode_call3(target, allow_failure, data)
        for target, allow_failure, data in calls
    ]

    offsets = []
    offset = 32 * len(encoded_calls)
    for encoded in encoded_calls:
        offsets.append(word(offset))
        offset += len(encoded)

    array_body = word(len(encoded_calls)) + b"".join(offsets) + b"".join(encoded_calls)
    return "0x" + (SELECTOR_AGGREGATE3 + word(32) + array_body).hex()


def calldata_no_args(selector: bytes) -> bytes:
    return selector


def calldata_with_uint256(selector: bytes, value: int) -> bytes:
    return selector + word(value)


def read_word(data: bytes, offset: int) -> int:
    end = offset + 32
    if end > len(data):
        raise ValueError("ABI decode out of bounds")
    return int.from_bytes(data[offset:end], byteorder="big")


def decode_aggregate3_return(hex_data: str) -> list[tuple[bool, bytes]]:
    data = bytes.fromhex(strip_0x(hex_data))
    if len(data) < 64:
        raise ValueError("short Multicall3 return data")

    array_start = read_word(data, 0)
    length = read_word(data, array_start)
    offsets_start = array_start + 32

    results: list[tuple[bool, bytes]] = []
    for i in range(length):
        tuple_start = offsets_start + read_word(data, offsets_start + (32 * i))
        success = read_word(data, tuple_start) != 0
        return_offset = read_word(data, tuple_start + 32)
        return_start = tuple_start + return_offset
        return_length = read_word(data, return_start)
        start = return_start + 32
        end = start + return_length
        if end > len(data):
            raise ValueError("ABI decode out of bounds")
        results.append((success, data[start:end]))

    return results


def decode_uint256(data: bytes) -> int:
    if len(data) < 32:
        raise ValueError("short uint256 return data")
    return read_word(data, 0)


def decode_withdrawal_request(request_id: int, data: bytes) -> WithdrawalRequest:
    if len(data) < 32 * 5:
        raise ValueError(f"short withdrawalRequests({request_id}) return data")

    shares = read_word(data, 160) if len(data) >= 32 * 6 else None
    queue_units = "shares" if shares is not None else "assets"

    raw_address = data[12:32].hex()
    return WithdrawalRequest(
        request_id=request_id,
        withdrawer="0x" + raw_address,
        claimed=read_word(data, 32) != 0,
        claim_timestamp=read_word(data, 64),
        assets=read_word(data, 96),
        queued=read_word(data, 128),
        shares=shares,
        queue_units=queue_units,
    )


class RpcClient:
    def __init__(self, rpc_url: str, timeout: int) -> None:
        self.rpc_url = rpc_url
        self.timeout = timeout
        self.next_id = 1

    def call(self, method: str, params: list[Any]) -> Any:
        payload = {
            "jsonrpc": "2.0",
            "id": self.next_id,
            "method": method,
            "params": params,
        }
        self.next_id += 1

        request = urllib.request.Request(
            self.rpc_url,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                body = json.loads(response.read().decode())
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace")
            raise RuntimeError(f"RPC HTTP {exc.code}: {detail}") from exc
        except urllib.error.URLError as exc:
            raise RuntimeError(f"RPC connection failed: {exc}") from exc

        if "error" in body:
            raise RuntimeError(f"RPC {method} error: {body['error']}")
        return body["result"]

    def eth_call(self, to: str, data: str, block_tag: str) -> str:
        return self.call("eth_call", [{"to": validate_address(to), "data": data}, block_tag])


def multicall(
    client: RpcClient,
    block_tag: str,
    calls: list[tuple[str, bytes]],
) -> list[bytes]:
    if not calls:
        return []

    data = encode_aggregate3((target, False, call_data) for target, call_data in calls)
    raw_result = client.eth_call(MULTICALL3, data, block_tag)
    results = decode_aggregate3_return(raw_result)

    if len(results) != len(calls):
        raise RuntimeError(f"Multicall3 returned {len(results)} results for {len(calls)} calls")

    failed = [i for i, (success, _) in enumerate(results) if not success]
    if failed:
        raise RuntimeError(f"Multicall3 subcalls failed at indices: {failed[:10]}")

    return [return_data for _, return_data in results]


def block_tag_from_args(client: RpcClient, block_arg: str) -> tuple[str, int, int]:
    if block_arg == "latest":
        block_number = int(client.call("eth_blockNumber", []), 16)
    else:
        block_number = int(block_arg, 0)

    block_tag = hex(block_number)
    block = client.call("eth_getBlockByNumber", [block_tag, False])
    if block is None:
        raise RuntimeError(f"block not found: {block_tag}")

    return block_tag, block_number, int(block["timestamp"], 16)


def fetch_snapshot(client: RpcClient, arm: str, block_tag: str, block_number: int, block_timestamp: int) -> Snapshot:
    call_results = multicall(
        client,
        block_tag,
        [
            (arm, calldata_no_args(SELECTOR_NEXT_WITHDRAWAL_INDEX)),
            (arm, calldata_no_args(SELECTOR_CLAIMABLE)),
            (arm, calldata_no_args(SELECTOR_CLAIM_DELAY)),
        ],
    )

    return Snapshot(
        block_number=block_number,
        block_timestamp=block_timestamp,
        next_withdrawal_index=decode_uint256(call_results[0]),
        claimable_frontier=decode_uint256(call_results[1]),
        claim_delay=decode_uint256(call_results[2]),
    )


def fetch_requests(
    client: RpcClient,
    arm: str,
    block_tag: str,
    start_id: int,
    end_id: int,
    batch_size: int,
) -> list[WithdrawalRequest]:
    requests: list[WithdrawalRequest] = []

    for batch_start in range(start_id, end_id, batch_size):
        batch_end = min(batch_start + batch_size, end_id)
        ids = list(range(batch_start, batch_end))
        calls = [
            (arm, calldata_with_uint256(SELECTOR_WITHDRAWAL_REQUESTS, request_id))
            for request_id in ids
        ]
        results = multicall(client, block_tag, calls)
        requests.extend(
            decode_withdrawal_request(request_id, result)
            for request_id, result in zip(ids, results, strict=True)
        )

    return requests


def iso_timestamp(timestamp: int | None) -> str:
    if timestamp is None:
        return ""
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).isoformat()


def format_units(value: int, decimals: int) -> str:
    scale = 10**decimals
    whole = value // scale
    fraction = value % scale
    if fraction == 0:
        return str(whole)

    fraction_text = str(fraction).rjust(decimals, "0").rstrip("0")
    return f"{whole}.{fraction_text}"


def request_status(request: WithdrawalRequest, snapshot: Snapshot) -> str:
    if request.claimed:
        return "claimed"
    if request.shares == 0:
        return "unclaimed_zero_shares"
    if request.claim_timestamp > snapshot.block_timestamp:
        return "waiting_delay"
    if request.queued > snapshot.claimable_frontier:
        return "waiting_liquidity"
    return "claimable_now"


def build_rows(
    requests: list[WithdrawalRequest],
    snapshot: Snapshot,
    decimals: int,
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for request in requests:
        requested_at = None
        if snapshot.claim_delay <= request.claim_timestamp:
            requested_at = request.claim_timestamp - snapshot.claim_delay

        status = request_status(request, snapshot)
        shares_raw = "" if request.shares is None else str(request.shares)
        shares = "" if request.shares is None else format_units(request.shares, decimals)
        rows.append(
            {
                "request_id": request.request_id,
                "withdrawer": request.withdrawer,
                "claimed": request.claimed,
                "status": status,
                "claimable_now": status == "claimable_now",
                "zero_shares": request.shares == 0,
                "queue_units": request.queue_units,
                "requested_at_utc": iso_timestamp(requested_at),
                "claimable_at_utc": iso_timestamp(request.claim_timestamp),
                "assets_raw": str(request.assets),
                "assets": format_units(request.assets, decimals),
                "queued_raw": str(request.queued),
                "queued": format_units(request.queued, decimals),
                "shares_raw": shares_raw,
                "shares": shares,
            }
        )
    return rows


def write_json(rows: list[dict[str, Any]], metadata: dict[str, Any], output_path: str | None) -> None:
    payload = {"metadata": metadata, "requests": rows}
    text = json.dumps(payload, indent=2)
    if output_path:
        Path(output_path).write_text(text + "\n")
    else:
        print(text)


def write_csv(rows: list[dict[str, Any]], output_path: str | None) -> None:
    fieldnames = [
        "request_id",
        "withdrawer",
        "claimed",
        "status",
        "claimable_now",
        "zero_shares",
        "queue_units",
        "requested_at_utc",
        "claimable_at_utc",
        "assets_raw",
        "assets",
        "queued_raw",
        "queued",
        "shares_raw",
        "shares",
    ]

    if output_path:
        output_file = Path(output_path).open("w", newline="")
        should_close = True
    else:
        output_file = sys.stdout
        should_close = False

    try:
        writer = csv.DictWriter(output_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    finally:
        if should_close:
            output_file.close()


def write_table(rows: list[dict[str, Any]], metadata: dict[str, Any], output_path: str | None) -> None:
    lines = [
        f"ARM: {metadata['arm']}",
        f"Block: {metadata['block_number']} ({metadata['block_timestamp_utc']})",
        f"Total requests: {metadata['next_withdrawal_index']}",
        f"Checked request ids: [{metadata['start_id']}, {metadata['end_id']})",
        (
            f"Open requests: {metadata['open_count']} | "
            f"claimable now: {metadata['claimable_now_count']} | "
            f"zero-share open: {metadata['zero_share_open_count']}"
        ),
        "",
    ]

    if not rows:
        lines.append("No matching requests.")
    else:
        columns = [
            ("request_id", "id"),
            ("withdrawer", "withdrawer"),
            ("status", "status"),
            ("queue_units", "queue"),
            ("assets", "assets"),
            ("shares", "shares"),
            ("claimable_at_utc", "claimable_at_utc"),
        ]

        widths = {
            key: max(len(label), *(len(str(row[key])) for row in rows))
            for key, label in columns
        }
        header = "  ".join(label.ljust(widths[key]) for key, label in columns)
        separator = "  ".join("-" * widths[key] for key, _ in columns)
        lines.extend([header, separator])
        for row in rows:
            lines.append("  ".join(str(row[key]).ljust(widths[key]) for key, _ in columns))

    text = "\n".join(lines)
    if output_path:
        Path(output_path).write_text(text + "\n")
    else:
        print(text)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch ARM withdrawalRequests via Multicall3 and list unclaimed requests.",
    )
    parser.add_argument(
        "--rpc-url",
        default=None,
        help="Ethereum RPC URL. Defaults to MAINNET_URL from env or .env.",
    )
    parser.add_argument(
        "--arm",
        default=DEFAULT_ARM,
        help=f"ARM address. Defaults to stETH ARM {DEFAULT_ARM}.",
    )
    parser.add_argument(
        "--block",
        default="latest",
        help="Block number or 'latest'. Calls are pinned to this block.",
    )
    parser.add_argument("--start-id", type=int, default=0, help="First request id to check, inclusive.")
    parser.add_argument(
        "--end-id",
        type=int,
        default=None,
        help="Last request id to check, exclusive. Defaults to nextWithdrawalIndex().",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=250,
        help="withdrawalRequests calls per Multicall3 aggregate3 call.",
    )
    parser.add_argument(
        "--decimals",
        type=int,
        default=18,
        help="Decimals used when formatting assets and shares.",
    )
    parser.add_argument("--include-claimed", action="store_true", help="Include claimed requests in the output.")
    parser.add_argument("--format", choices=["table", "json", "csv"], default="table", help="Output format.")
    parser.add_argument("--out", default=None, help="Optional output file.")
    return parser.parse_args()


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    load_dotenv(repo_root / ".env")
    args = parse_args()

    if args.start_id < 0:
        raise ValueError("--start-id must be >= 0")
    if args.end_id is not None and args.end_id < args.start_id:
        raise ValueError("--end-id must be >= --start-id")
    if args.batch_size <= 0:
        raise ValueError("--batch-size must be > 0")

    rpc_url = args.rpc_url or os.environ.get("MAINNET_URL")
    if not rpc_url:
        raise RuntimeError("missing RPC URL. Set MAINNET_URL in .env/env or pass --rpc-url.")

    arm = validate_address(args.arm)
    client = RpcClient(rpc_url, timeout=90)

    block_tag, block_number, block_timestamp = block_tag_from_args(client, args.block)
    snapshot = fetch_snapshot(client, arm, block_tag, block_number, block_timestamp)

    end_id = args.end_id if args.end_id is not None else snapshot.next_withdrawal_index
    if end_id > snapshot.next_withdrawal_index:
        raise ValueError(f"--end-id exceeds nextWithdrawalIndex ({snapshot.next_withdrawal_index})")

    all_requests = fetch_requests(client, arm, block_tag, args.start_id, end_id, args.batch_size)
    selected = all_requests if args.include_claimed else [request for request in all_requests if not request.claimed]
    rows = build_rows(selected, snapshot, args.decimals)

    open_count = sum(1 for request in all_requests if not request.claimed)
    claimable_now_count = sum(1 for request in all_requests if request_status(request, snapshot) == "claimable_now")
    zero_share_open_count = sum(
        1
        for request in all_requests
        if not request.claimed and request.shares == 0
    )
    metadata = {
        "arm": arm,
        "block_number": snapshot.block_number,
        "block_timestamp": snapshot.block_timestamp,
        "block_timestamp_utc": iso_timestamp(snapshot.block_timestamp),
        "next_withdrawal_index": snapshot.next_withdrawal_index,
        "claimable_frontier_raw": str(snapshot.claimable_frontier),
        "claimable_frontier": format_units(snapshot.claimable_frontier, args.decimals),
        "claim_delay": snapshot.claim_delay,
        "start_id": args.start_id,
        "end_id": end_id,
        "open_count": open_count,
        "claimable_now_count": claimable_now_count,
        "zero_share_open_count": zero_share_open_count,
    }

    if args.format == "json":
        write_json(rows, metadata, args.out)
    elif args.format == "csv":
        write_csv(rows, args.out)
    else:
        write_table(rows, metadata, args.out)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
