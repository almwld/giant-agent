import os
import sys
from reportlab.pdfgen import canvas
import tempfile
import unittest
import zipfile

from document_parser import extract_document


class DocumentParserTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)

    def path(self, name):
        return os.path.join(self.temp.name, name)

    def make_docx(self, path):
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(
                "word/document.xml",
                '<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Giant Agent DOCX</w:t></w:r></w:p></w:body></w:document>',
            )

    def make_xlsx(self, path):
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr(
                "xl/workbook.xml",
                '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Summary" sheetId="1" r:id="rId1"/></sheets></workbook>',
            )
            archive.writestr(
                "xl/_rels/workbook.xml.rels",
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Target="worksheets/sheet1.xml" Type="worksheet"/></Relationships>',
            )
            archive.writestr(
                "xl/sharedStrings.xml",
                '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>Revenue</t></si></sst>',
            )
            archive.writestr(
                "xl/worksheets/sheet1.xml",
                '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><v>250</v></c></row></sheetData></worksheet>',
            )

    def test_pdf_extracts_page_text(self):
        path = self.path("sample.pdf")
        document = canvas.Canvas(path)
        document.drawString(72, 720, "Giant Agent PDF")
        document.save()
        result = extract_document(path)
        self.assertEqual(result["format"], "pdf")
        self.assertIn("[Page 1]", result["text"])
        self.assertIn("Giant Agent PDF", result["text"])

    def test_docx_extracts_paragraph_text(self):
        path = self.path("sample.docx")
        self.make_docx(path)
        result = extract_document(path)
        self.assertEqual(result["format"], "docx")
        self.assertIn("Giant Agent DOCX", result["text"])

    def test_xlsx_extracts_sheet_and_cells(self):
        path = self.path("sample.xlsx")
        self.make_xlsx(path)
        result = extract_document(path)
        self.assertIn("[Sheet: Summary]", result["text"])
        self.assertIn("Revenue\t250", result["text"])

    def test_rejects_unsupported_extension(self):
        path = self.path("sample.bin")
        with open(path, "wb") as file:
            file.write(b"not a supported document")
        with self.assertRaises(ValueError):
            extract_document(path)

    def test_rejects_oversized_input(self):
        path = self.path("large.docx")
        with open(path, "wb") as file:
            file.truncate(8 * 1024 * 1024 + 1)
        with self.assertRaises(ValueError):
            extract_document(path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
