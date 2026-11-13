#!/usr/bin/env python3
"""Instrument the fixed pre-optimization worktree without changing its behavior."""
from pathlib import Path
import shutil,sys
current=Path(__file__).resolve().parents[1]
baseline=Path(sys.argv[1]).resolve()
assert (baseline/'.git').exists()
for name in ['ReaderPerformance.swift','ReaderPerformanceSeed.swift']:
 shutil.copyfile(current/'QingRead/Services'/name,baseline/'QingRead/Services'/name)
ui=(current/'QingReadUITests/ReaderScrollPerformanceTests.swift').read_text().replace('private let baseline = false','private let baseline = true')
(baseline/'QingReadUITests/ReaderScrollPerformanceTests.swift').write_text(ui)
def edit(path,old,new):
 p=baseline/path;s=p.read_text();assert old in s,(path,'baseline instrumentation anchor missing');p.write_text(s.replace(old,new,1))
edit('QingRead/Views/RootView.swift','await library.seedBrandBooksIfRequested()','await library.seedBrandBooksIfRequested()\n            await library.seedReaderPerformanceIfRequested()')
edit('QingRead/Services/ReaderSession.swift','let text = library.chapterText(for: chapter, book: book)','let text = ReaderPerformance.measure(.fileRead) { library.chapterText(for: chapter, book: book) }')
edit('QingRead/Services/ReaderSession.swift','library.update(position: newPosition, for: book)','ReaderPerformance.measure(.progressCommit) { library.update(position: newPosition, for: book) }')
p=baseline/'QingRead/Services/Paginator.swift';s=p.read_text()
needle='    static func attributed(_ text: String, settings: ReaderSettings, chapterTitle: String? = nil) -> NSAttributedString {'
assert needle in s
s=s.replace(needle,'''    static func attributed(_ text: String, settings: ReaderSettings, chapterTitle: String? = nil) -> NSAttributedString {
        ReaderPerformance.measure(.attributedText) { baselineAttributed(text, settings: settings, chapterTitle: chapterTitle) }
    }
    private static func baselineAttributed(_ text: String, settings: ReaderSettings, chapterTitle: String?) -> NSAttributedString {''',1)
needle='    static func layout(_ text: String, size: CGSize, settings: ReaderSettings, chapterTitle: String? = nil) -> TextLayout {'
assert needle in s
s=s.replace(needle,'''    static func layout(_ text: String, size: CGSize, settings: ReaderSettings, chapterTitle: String? = nil) -> TextLayout {
        ReaderPerformance.measure(.pagination) { baselineLayout(text, size: size, settings: settings, chapterTitle: chapterTitle) }
    }
    private static func baselineLayout(_ text: String, size: CGSize, settings: ReaderSettings, chapterTitle: String?) -> TextLayout {''',1)
p.write_text(s)
edit('QingRead/Views/ScrollTextCell.swift','    func configure(text: NSAttributedString, settings: ReaderSettings) {','''    func configure(text: NSAttributedString, settings: ReaderSettings) {
        ReaderPerformance.measure(.cellConfiguration) { baselineConfigure(text: text, settings: settings) }
    }
    private func baselineConfigure(text: NSAttributedString, settings: ReaderSettings) {''')
edit('QingRead/Views/NativeReader.swift','    private var coverPan: UIPanGestureRecognizer?','    private var coverPan: UIPanGestureRecognizer?\n    private let frameProbe = ReaderFrameProbe()')
edit('QingRead/Views/NativeReader.swift','    override func viewDidLayoutSubviews() {','''    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); frameProbe.stop()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); if let table { frameProbe.attach(to: table) }
    }
    override func viewDidLayoutSubviews() {''')
edit('QingRead/Views/NativeReader.swift','self.table = table; scrollRows = []; appendScrollChapter(current.chapter); view.addSubview(table)','''self.table = table; scrollRows = []; appendScrollChapter(current.chapter); view.addSubview(table)
        frameProbe.attach(to: table)
        if let layout = layouts[current.chapter], let range = layout.ranges.first {
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(layout.attributed), CFRange(location: range.start, length: range.length), CGPath(rect: CGRect(origin: .zero, size: layout.size), transform: nil), nil)
            ReaderPerformanceRecorder.shared.recordViewport(width: view.bounds.width, height: view.bounds.height, visibleLines: CFArrayGetCount(CTFrameGetLines(frame)))
        }''')
edit('QingRead/Views/NativeReader.swift','    private func appendScrollChapter(_ index: Int) {','''    private func appendScrollChapter(_ index: Int) {
        ReaderPerformance.measure(.chapterUpdate) { baselineAppendChapter(index) }
    }
    private func baselineAppendChapter(_ index: Int) {''')
edit('QingRead/Views/NativeReader.swift','    func scrollViewDidScroll(_ scrollView: UIScrollView) {','''    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        ReaderPerformance.measure(.scrollCallback) { baselineDidScroll(scrollView) }
    }
    private func baselineDidScroll(_ scrollView: UIScrollView) {''')
print('Baseline retains d75d7b6 behavior; added timing/signpost/frame sampling and the identical synthetic touch tests only.')
