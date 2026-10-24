"""Attachment text-extraction tests using in-memory generated files."""

from __future__ import annotations

import base64
import io

import pytest

from outlook_triage_mcp.attachments import extract_text, fetch_attachment_texts

openpyxl = pytest.importorskip("openpyxl")
docx = pytest.importorskip("docx")
pypdf = pytest.importorskip("pypdf")


def make_xlsx_bytes() -> bytes:
    workbook = openpyxl.Workbook()
    sheet = workbook.active
    sheet.title = "Data"
    sheet.append(["metric", "value"])
    sheet.append(["revenue", 1234])
    buffer = io.BytesIO()
    workbook.save(buffer)
    return buffer.getvalue()


def make_docx_bytes() -> bytes:
    document = docx.Document()
    document.add_paragraph("Quarterly summary paragraph.")
    table = document.add_table(rows=1, cols=2)
    table.rows[0].cells[0].text = "item"
    table.rows[0].cells[1].text = "count"
    buffer = io.BytesIO()
    document.save(buffer)
    return buffer.getvalue()


def make_blank_pdf_bytes() -> bytes:
    writer = pypdf.PdfWriter()
    writer.add_blank_page(width=200, height=200)
    buffer = io.BytesIO()
    writer.write(buffer)
    return buffer.getvalue()


def test_xlsx_extraction():
    text = extract_text("report.xlsx", "", make_xlsx_bytes())
    assert "Sheet: Data" in text
    assert "revenue | 1234" in text


def test_docx_extraction():
    text = extract_text("summary.docx", "", make_docx_bytes())
    assert "Quarterly summary paragraph." in text
    assert "item | count" in text


def test_pdf_without_text_reports_gracefully():
    text = extract_text("scan.pdf", "application/pdf", make_blank_pdf_bytes())
    assert "no extractable text" in text


def test_unsupported_type_is_listed_not_parsed():
    text = extract_text("archive.zip", "application/zip", b"PK\x03\x04")
    assert "not parsed" in text


class AttachmentFakeGraph:
    def __init__(self, attachments):
        self._attachments = attachments

    def get(self, path, params=None, headers=None):
        assert path.endswith("/attachments")
        return {"value": self._attachments}


def test_fetch_attachment_texts_end_to_end():
    graph = AttachmentFakeGraph(
        [
            {
                "@odata.type": "#microsoft.graph.fileAttachment",
                "name": "numbers.xlsx",
                "size": 2048,
                "contentType": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "contentBytes": base64.b64encode(make_xlsx_bytes()).decode(),
            },
            {
                "@odata.type": "#microsoft.graph.fileAttachment",
                "name": "huge.pdf",
                "size": 50 * 1024 * 1024,
                "contentType": "application/pdf",
                "contentBytes": "",
            },
            {
                "@odata.type": "#microsoft.graph.itemAttachment",
                "name": "forwarded message",
                "size": 100,
                "contentType": "",
            },
        ]
    )
    results = fetch_attachment_texts(graph, "msg-1", max_bytes=5 * 1024 * 1024)
    assert len(results) == 3
    assert "revenue | 1234" in results[0]["text"]
    assert "too large" in results[1]["text"]
    assert "non-file" in results[2]["text"]
