#!/usr/bin/env python3
"""Create an original, tiny EPUB 3 publication for automated tests."""
from pathlib import Path
from zipfile import ZipFile, ZIP_STORED, ZIP_DEFLATED
entries = {
'META-INF/container.xml': '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
'OEBPS/content.opf': '<?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">urn:uuid:546e37fe-3d4a-4da6-b092-184e34e2e841</dc:identifier><dc:title>原创测试书</dc:title><dc:creator>测试作者</dc:creator><dc:language>zh-CN</dc:language><meta property="dcterms:modified">2026-11-12T00:00:00Z</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/><item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/><item id="image" href="image.svg" media-type="image/svg+xml"/></manifest><spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>',
'OEBPS/nav.xhtml': '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>目录</title></head><body><nav epub:type="toc"><ol><li><a href="c1.xhtml">第一章 出发</a></li><li><a href="c2.xhtml">第二章 归来</a></li></ol></nav></body></html>',
'OEBPS/c1.xhtml': '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章 出发</title></head><body><h1>第一章 出发</h1><p>这是专为自动测试原创的短文。清晨，小舟驶向湖心。</p><img src="image.svg" alt="测试图形"/></body></html>',
'OEBPS/c2.xhtml': '<?xml version="1.0" encoding="UTF-8"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>第二章 归来</title></head><body><h1>第二章 归来</h1><p>傍晚，船回到了岸边。测试结束。</p></body></html>',
'OEBPS/image.svg': '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"><rect width="200" height="100" fill="#d4dfcc"/><circle cx="100" cy="50" r="25" fill="#456650"/></svg>'
}
path = Path(__file__).resolve().parents[1] / 'QingReadTests/Fixtures/OriginalFixture.epub'
path.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(path, 'w') as archive:
    archive.writestr('mimetype', 'application/epub+zip', compress_type=ZIP_STORED)
    for name, text in entries.items():
        archive.writestr(name, text.encode(), compress_type=ZIP_DEFLATED)
print(path)
