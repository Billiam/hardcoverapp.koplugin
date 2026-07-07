import zipfile

CONTAINER = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>"""

OPF = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uid" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Journal Export Test Book</dc:title>
    <dc:creator>Test Author</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="uid">journal-export-test-1</dc:identifier>
  </metadata>
  <manifest>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>"""

paragraphs = "\n".join(
    f"<p>Paragraph {i}: some reading material to fill a handful of pages. "
    "The quick brown fox jumps over the lazy dog again and again.</p>"
    for i in range(1, 200)
)
CH1 = f"""<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter One</title></head>
<body><h1>Chapter One</h1>{paragraphs}</body>
</html>"""

with zipfile.ZipFile("/test/book.epub", "w") as z:
    z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    z.writestr("META-INF/container.xml", CONTAINER)
    z.writestr("OEBPS/content.opf", OPF)
    z.writestr("OEBPS/ch1.xhtml", CH1)
print("epub written")
