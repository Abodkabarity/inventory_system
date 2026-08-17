"""Sync yesterday's ERP item-not-found report to Supabase.

The existing credentials/configuration are imported from automation/main.py so
they are not duplicated here.

Examples:
    python automation/missing_items_sync.py
    python automation/missing_items_sync.py --date 2026-07-13 --dry-run
    python automation/missing_items_sync.py --save-xlsx missing_items.xlsx
"""

from __future__ import annotations

import argparse
import math
import re
import warnings
from datetime import date, datetime, timedelta
from io import BytesIO
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs
from zoneinfo import ZoneInfo

import pandas as pd
import requests
from playwright.sync_api import Page, sync_playwright

from main import BASE_URL, PASSWORD, SUPABASE_KEY, SUPABASE_URL, USERNAME


warnings.filterwarnings(
    "ignore",
    message="Workbook contains no default style, apply openpyxl's default",
    module="openpyxl.styles.stylesheet",
)


REPORT_URL = (
    "https://zas.proactiveerp.com/Inventroy/"
    "POS_InvoiceItemNotFoundRequestPage.aspx"
)
TIME_ZONE = ZoneInfo("Asia/Dubai")
REQUEST_TIMEOUT_MS = 360_000
REQUEST_TIMEOUT_SECONDS = 300

FIELD_IDS = {
    "from_date": "#ctl00_ContentPlaceHolder1_DatFromDate",
    "to_date": "#ctl00_ContentPlaceHolder1_DatToDate",
    "branch": "#ctl00_ContentPlaceHolder1_ddlBranch",
    "status": "#ctl00_ContentPlaceHolder1_ddlStatus",
    "reason": "#ctl00_ContentPlaceHolder1_ddlItemNotFoundReason",
    "request_needed": (
        "#ctl00_ContentPlaceHolder1_ddlItemNotFoundRequestNeeded"
    ),
    "refresh": "#bntGVRefresh",
    "xlsx": "#ctl00_ContentPlaceHolder1_GridSetting_btnXlsxExport",
}

COLUMN_ALIASES = {
    "warehouse": "warehouse",
    "sales man": "sales_man",
    "salesman": "sales_man",
    "item code": "item_code",
    "item name": "item_name",
    "barcode": "barcode",
    "description": "description",
    "request type": "request_type",
    "action needed": "action_needed",
    "required quantity": "required_quantity",
    "required qty": "required_quantity",
    "added date": "added_date",
    "added user name": "added_user_name",
    "added username": "added_user_name",
    "notes": "notes",
    "note": "notes",
}

OUTPUT_COLUMNS = [
    "warehouse",
    "sales_man",
    "item_code",
    "item_name",
    "barcode",
    "description",
    "request_type",
    "action_needed",
    "required_quantity",
    "added_date",
    "added_user_name",
    "notes",
]


def _login(page: Page, company_name: str | None) -> None:
    page.goto(BASE_URL, wait_until="domcontentloaded", timeout=120_000)
    page.fill("#txtUserName", USERNAME)
    page.fill("#txtPassword", PASSWORD)
    page.click("#btnLogin")
    page.wait_for_selector("select", state="visible", timeout=120_000)
    if company_name:
        page.select_option("select", label=company_name)
    page.click("#btnSelectCompany")
    page.wait_for_load_state("networkidle", timeout=120_000)


def download_report(report_date: date, company_name: str | None = None) -> bytes:
    """Use the real WebForms controls so VIEWSTATE/postback stays valid."""
    date_text = report_date.isoformat()
    print("[1/4] Logging in to Proactive ERP...")
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        context = browser.new_context(accept_downloads=True)
        page = context.new_page()
        _login(page, company_name)

        print(f"[2/4] Loading report for {date_text}...")
        page.goto(REPORT_URL, wait_until="networkidle", timeout=120_000)
        # The page's datepicker restores today's HTML value on blur. Updating
        # both the live property and the value attribute prevents that reset.
        for field in ("from_date", "to_date"):
            page.locator(FIELD_IDS[field]).evaluate(
                "(element, value) => {"
                "element.value = value;"
                "element.setAttribute('value', value);"
                "}",
                date_text,
            )
        page.select_option(FIELD_IDS["branch"], value="0")
        page.select_option(FIELD_IDS["status"], value="1")
        page.select_option(FIELD_IDS["reason"], value="0")
        page.select_option(FIELD_IDS["request_needed"], value="0")

        print("[3/4] Refreshing report filters...")
        with page.expect_response(
            lambda response: (
                REPORT_URL.lower() in response.url.lower()
                and response.request.method == "POST"
            ),
            timeout=REQUEST_TIMEOUT_MS,
        ) as refresh_info:
            page.click(FIELD_IDS["refresh"])
        refresh_response = refresh_info.value
        refresh_response.body()  # Wait until the Microsoft AJAX response ends.
        if refresh_response.status != 200:
            raise RuntimeError(
                f"ERP refresh failed with HTTP {refresh_response.status}."
            )
        posted_fields = parse_qs(
            refresh_response.request.post_data or "",
            keep_blank_values=True,
        )
        posted_from = posted_fields.get(
            "ctl00$ContentPlaceHolder1$DatFromDate", [""]
        )[0]
        posted_to = posted_fields.get(
            "ctl00$ContentPlaceHolder1$DatToDate", [""]
        )[0]
        if posted_from != date_text or posted_to != date_text:
            raise RuntimeError(
                "ERP changed the requested report date before refresh: "
                f"expected {date_text}, sent {posted_from} to {posted_to}."
            )
        print(f"      Confirmed ERP payload date: {posted_from}.")

        print("[4/4] Downloading Excel...")
        with page.expect_download(timeout=REQUEST_TIMEOUT_MS) as download_info:
            page.click(FIELD_IDS["xlsx"])
        download = download_info.value
        failure = download.failure()
        if failure:
            raise RuntimeError(f"ERP Excel download failed: {failure}")
        temp_path = download.path()
        if temp_path is None:
            raise RuntimeError("ERP download completed without a local file.")
        file_bytes = temp_path.read_bytes()
        browser.close()

    if not file_bytes.startswith((b"PK\x03\x04", bytes.fromhex("D0CF11E0"))):
        raise RuntimeError("ERP download is not a valid Excel file.")
    print(f"      Downloaded {len(file_bytes):,} bytes.")
    return file_bytes


def _normalize_header(value: Any) -> str:
    if pd.isna(value):
        return ""
    return re.sub(r"[^a-z0-9]+", " ", str(value).strip().lower()).strip()


def _text(value: Any) -> str:
    if value is None or pd.isna(value):
        return ""
    if isinstance(value, float) and math.isfinite(value) and value.is_integer():
        return str(int(value))
    return str(value).strip()


def _identifier_text(value: Any) -> str:
    """Convert ERP placeholder identifiers to a genuinely empty value."""
    text = _text(value)
    if text.casefold() in {"-", "--", "n/a", "na", "null", "none"}:
        return ""
    return text


def _quantity(value: Any) -> int | float | None:
    if value is None or pd.isna(value) or _text(value) == "":
        return None
    number = float(str(value).replace(",", "").strip())
    return int(number) if number.is_integer() else number


def _date_time(value: Any) -> str | None:
    if value is None or pd.isna(value) or _text(value) == "":
        return None
    parsed = pd.to_datetime(value, errors="coerce", dayfirst=True)
    if pd.isna(parsed):
        raise ValueError(f"Invalid Added Date value: {value!r}")
    timestamp = pd.Timestamp(parsed)
    if timestamp.tzinfo is None:
        timestamp = timestamp.tz_localize(TIME_ZONE)
    else:
        timestamp = timestamp.tz_convert(TIME_ZONE)
    return timestamp.isoformat()


def parse_report(file_bytes: bytes) -> list[dict[str, Any]]:
    """Locate the real header row and map the 12 requested report columns."""
    raw = pd.read_excel(BytesIO(file_bytes), header=None, dtype=object)
    header_row: int | None = None
    column_indexes: dict[str, int] = {}

    for row_index in range(min(30, len(raw.index))):
        candidate: dict[str, int] = {}
        for column_index, value in enumerate(raw.iloc[row_index].tolist()):
            mapped = COLUMN_ALIASES.get(_normalize_header(value))
            if mapped and mapped not in candidate:
                candidate[mapped] = column_index
        if {"warehouse", "item_code", "item_name"}.issubset(candidate):
            header_row = row_index
            column_indexes = candidate
            break

    if header_row is None:
        raise RuntimeError("Could not locate the missing-items header row in Excel.")

    missing = [name for name in OUTPUT_COLUMNS if name not in column_indexes]
    if missing:
        raise RuntimeError("Excel is missing expected columns: " + ", ".join(missing))

    records: list[dict[str, Any]] = []
    for row_index in range(header_row + 1, len(raw.index)):
        row = raw.iloc[row_index]
        record: dict[str, Any] = {
            name: _text(row.iloc[column_indexes[name]]) for name in OUTPUT_COLUMNS
        }
        record["item_code"] = _identifier_text(record["item_code"])
        record["item_name"] = _identifier_text(record["item_name"])
        # Ignore report footers and other non-product rows. A warehouse label
        # alone is not enough to identify a missing item.
        if not any(record[name] for name in ("item_code", "item_name")):
            continue
        record["required_quantity"] = _quantity(
            row.iloc[column_indexes["required_quantity"]]
        )
        record["added_date"] = _date_time(
            row.iloc[column_indexes["added_date"]]
        )
        records.append(record)

    print(f"      Parsed {len(records):,} source rows.")
    return deduplicate_products(records)


def _product_key(value: Any) -> str:
    """Normalize ERP codes/names for stable duplicate matching."""
    return re.sub(r"\s+", " ", _text(value)).strip().casefold()


def deduplicate_products(
    records: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Deduplicate only an exact branch + item code + item name identity.

    Products sharing a code, a name, or a branch independently remain separate.
    This is especially important for ERP rows whose missing code is represented
    by a dash. For a true duplicate, the latest request is retained while blank
    fields are completed from the older occurrence.
    """
    unique: list[dict[str, Any]] = []
    index_by_identity: dict[tuple[str, str, str], int] = {}

    for source_record in records:
        record = dict(source_record)
        identity = (
            _product_key(record.get("warehouse")),
            _product_key(_identifier_text(record.get("item_code"))),
            _product_key(_identifier_text(record.get("item_name"))),
        )
        existing_index = index_by_identity.get(identity)

        if existing_index is None:
            existing_index = len(unique)
            unique.append(record)
            index_by_identity[identity] = existing_index
        else:
            previous = unique[existing_index]
            previous_date = previous.get("added_date") or ""
            current_date = record.get("added_date") or ""
            latest, older = (
                (record, previous)
                if current_date >= previous_date
                else (previous, record)
            )
            merged = dict(latest)
            for field, value in older.items():
                if merged.get(field) in (None, "") and value not in (None, ""):
                    merged[field] = value
            unique[existing_index] = merged

    duplicate_count = len(records) - len(unique)
    print(
        f"      Unique products: {len(unique):,} "
        f"({duplicate_count:,} duplicate rows removed)."
    )
    return unique


def replace_supabase_snapshot(
    report_date: date, records: list[dict[str, Any]]
) -> int:
    """Atomically delete/reinsert one report date through the SQL RPC."""
    print("Uploading an atomic snapshot to Supabase...")
    response = requests.post(
        f"{SUPABASE_URL}/rest/v1/rpc/replace_missing_items",
        headers={
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Content-Type": "application/json",
        },
        json={"p_report_date": report_date.isoformat(), "p_rows": records},
        timeout=REQUEST_TIMEOUT_SECONDS,
    )
    if response.status_code not in {200, 201, 204}:
        raise RuntimeError(
            "Supabase replacement failed. Run "
            "supabase/sql/missing_items.sql first. "
            f"HTTP {response.status_code}: {response.text}"
        )
    inserted = int(response.json() or 0) if response.content else len(records)
    print(f"      Inserted {inserted:,} rows for {report_date.isoformat()}.")
    return inserted


def _default_report_date() -> date:
    return datetime.now(TIME_ZONE).date() - timedelta(days=1)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync yesterday's ERP missing-items report to Supabase."
    )
    parser.add_argument(
        "--date",
        type=date.fromisoformat,
        default=_default_report_date(),
        help="Report date as YYYY-MM-DD (default: yesterday in Dubai).",
    )
    parser.add_argument(
        "--company",
        help="Optional exact company label from the ERP company selector.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Download and validate without changing Supabase.",
    )
    parser.add_argument(
        "--save-xlsx",
        type=Path,
        help="Optionally save the downloaded source Excel file.",
    )
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    file_bytes = download_report(args.date, args.company)
    if args.save_xlsx:
        args.save_xlsx.parent.mkdir(parents=True, exist_ok=True)
        args.save_xlsx.write_bytes(file_bytes)
        print(f"      Source Excel saved to {args.save_xlsx.resolve()}.")
    records = parse_report(file_bytes)
    if args.dry_run:
        print("Dry run complete; Supabase was not changed.")
        return
    replace_supabase_snapshot(args.date, records)
    print("Missing-items sync completed successfully.")


if __name__ == "__main__":
    main()
