import os
import zipfile
import xml.etree.ElementTree as ET
import posixpath

MAX_INPUT = 8 * 1024 * 1024
MAX_EXPANDED = 32 * 1024 * 1024
MAX_OUTPUT = 100000
W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
S = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"

def _archive(path):
    z = zipfile.ZipFile(path, "r")
    items = z.infolist()
    if len(items) > 2000 or sum(x.file_size for x in items) > MAX_EXPANDED:
        z.close()
        raise ValueError("Office document archive exceeds safety limits.")
    for item in items:
        name = item.filename.replace("\\", "/")
        if name.startswith("/") or ".." in name.split("/"):
            z.close()
            raise ValueError("Unsafe archive entry.")
    return z

def _docx(path):
    with _archive(path) as z:
        root = ET.fromstring(z.read("word/document.xml"))
        return "\n".join("".join(n.text or "" for n in p.iter(W + "t")) for p in root.iter(W + "p"))

def _xlsx(path):
    with _archive(path) as z:
        workbook = ET.fromstring(z.read("xl/workbook.xml"))
        rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
        targets = {x.attrib["Id"]: x.attrib["Target"] for x in rels}
        shared = []
        try:
            strings = ET.fromstring(z.read("xl/sharedStrings.xml"))
            shared = ["".join(n.text or "" for n in item.iter(S + "t")) for item in strings.findall(S + "si")]
        except KeyError:
            pass
        result = []
        for sheet in workbook.find(S + "sheets") or []:
            name = sheet.attrib.get("name", "Sheet")
            target = targets.get(sheet.attrib.get(R + "id"), "")
            if not target or target.startswith("/"):
                continue
            part = posixpath.normpath(posixpath.join("xl", target))
            if not part.startswith("xl/") or part.startswith("../"):
                continue
            root = ET.fromstring(z.read(part))
            result.append("[Sheet: " + name + "]")
            for row in root.iter(S + "row"):
                values = []
                for cell in row.findall(S + "c"):
                    value = cell.find(S + "v")
                    text = "" if value is None else (value.text or "")
                    if cell.attrib.get("t") == "s" and text:
                        try:
                            text = shared[int(text)]
                        except (ValueError, IndexError):
                            text = ""
                    elif cell.attrib.get("t") == "inlineStr":
                        inline = cell.find(S + "is")
                        text = "" if inline is None else "".join(n.text or "" for n in inline.iter(S + "t"))
                    values.append(text)
                if any(values):
                    result.append("\t".join(values))
        return "\n".join(result)

def _pdf(path):
    from pypdf import PdfReader
    reader = PdfReader(path, strict=False)
    if len(reader.pages) > 500:
        raise ValueError("PDF exceeds the 500-page extraction limit.")
    if reader.is_encrypted and not reader.decrypt(""):
        raise ValueError("Password-protected PDF is not supported.")
    pages = []
    for index, page in enumerate(reader.pages):
        value = page.extract_text() or ""
        if value.strip():
            pages.append("[Page %d]\n%s" % (index + 1, value))
    return "\n\n".join(pages)

def extract_document(path):
    if not isinstance(path, str) or not os.path.isfile(path):
        raise ValueError("Document path does not exist.")
    size = os.path.getsize(path)
    if size < 1 or size > MAX_INPUT:
        raise ValueError("Document must be between 1 byte and 8 MB.")
    extension = os.path.splitext(path)[1].lower()
    if extension == ".pdf":
        text = _pdf(path)
    elif extension == ".docx":
        text = _docx(path)
    elif extension == ".xlsx":
        text = _xlsx(path)
    else:
        raise ValueError("Only PDF, DOCX and XLSX are supported.")
    if not text.strip():
        raise ValueError("No extractable text was found. Scanned/image-only PDFs require OCR.")
    length = len(text)
    return {"text": text[:MAX_OUTPUT], "characters_extracted": length,
            "truncated": length > MAX_OUTPUT, "file_size": size,
            "format": extension[1:]}
