#!/usr/bin/env python3
"""Linux checks. Does not claim to typecheck UIKit or run Xcode."""
import hashlib, json, plistlib, struct, subprocess, zipfile, xml.etree.ElementTree as ET
from pathlib import Path
root=Path(__file__).resolve().parents[1]
plist=plistlib.loads((root/'QingRead/Info.plist').read_bytes())
assert plist['CFBundleExecutable']=='$(EXECUTABLE_NAME)'
assert len(plist['CFBundleDocumentTypes'])==2
assert plist['UIAppFonts']==['NotoSerifSC.ttf']
assert plist['CFBundleDisplayName']=='予盈'
assert plist['UILaunchStoryboardName']=='LaunchScreen'
ET.parse(root/'QingRead/Resources/LaunchScreen.storyboard')
icon_lock=json.loads((root/'design/yuying-vector/asset-lock.json').read_text())
icon_data=(root/icon_lock['png']).read_bytes()
assert hashlib.sha256(icon_data).hexdigest()==icon_lock['pngSHA256']
assert hashlib.sha256((root/icon_lock['source']).read_bytes()).hexdigest()==icon_lock['sourceSHA256']
assert struct.unpack_from('>IIBB',icon_data,16)==(1024,1024,8,2)  # 8-bit RGB, no alpha
icon_svg=ET.parse(root/icon_lock['source']).getroot()
assert icon_svg.attrib['viewBox']=='0 0 1024 1024'
assert not icon_svg.findall('.//{http://www.w3.org/2000/svg}image')
assert not icon_svg.findall('.//{http://www.w3.org/2000/svg}text')
assert icon_lock['alpha'] is False and icon_lock['bakedSystemCorners'] is False
for path in (root/'QingRead').rglob('*.swift'):
    assert '阅简' not in path.read_text(), f'Old visible brand in {path}'
plistlib.loads((root/'QingRead/PrivacyInfo.xcprivacy').read_bytes())
font=json.loads((root/'docs/font-lock.json').read_text())
assert hashlib.sha256((root/'QingRead/Resources/Fonts/NotoSerifSC.ttf').read_bytes()).hexdigest()==font['sha256']
lock=json.loads((root/'Package.resolved').read_text())
for pin in lock['pins']:
    assert len(pin['state']['revision'])==40
    assert (root/'QingRead/Resources/Notices'/(pin['identity']+'-LICENSE.txt')).stat().st_size>100
with zipfile.ZipFile(root/'QingReadTests/Fixtures/OriginalFixture.epub') as z:
    assert z.read('mimetype')==b'application/epub+zip'
    assert z.testzip() is None
    assert len(z.namelist())==7
subprocess.run(['bash','-n',str(root/'scripts/fetch-ipa.sh')],check=True)
subprocess.run(['git','diff','--check'],cwd=root,check=True)
print('PASS: plist, font checksum, dependency pins/notices, EPUB fixture, shell syntax, whitespace')
print('iOS compilation and XCTest must run on GitHub macOS, not Linux.')
