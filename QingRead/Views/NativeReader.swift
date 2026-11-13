import SwiftUI
import UIKit
import CoreText

struct NativeReader: UIViewControllerRepresentable {
    @ObservedObject var session: ReaderSession
    var settings: ReaderSettings
    func makeUIViewController(context: Context) -> NativeReaderController {
        NativeReaderController(session: session, settings: settings)
    }
    func updateUIViewController(_ controller: NativeReaderController, context: Context) {
        controller.apply(settings: settings)
    }
    static func dismantleUIViewController(_ controller: NativeReaderController, coordinator: ()) { controller.endReading() }
}

private struct PageAddress: Equatable { var chapter: Int; var page: Int }
private final class PrintedPage: UIViewController {
    let address: PageAddress
    let layout: TextLayout
    let settings: ReaderSettings
    init(address: PageAddress, layout: TextLayout, settings: ReaderSettings) {
        self.address = address; self.layout = layout; self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func loadView() {
        let canvas = CoreTextCanvas()
        canvas.layout = layout; canvas.range = layout.ranges[address.page]; canvas.padding = settings.sidePadding
        canvas.backgroundColor = settings.theme.uiBackground; canvas.isOpaque = true
        canvas.accessibilityIdentifier = "reader.content"
        canvas.accessibilityLabel = "正文"
        #if DEBUG
        canvas.accessibilityLabel = "正文，UTF16 \(canvas.range.start) \(canvas.range.end)"
        #endif
        canvas.isAccessibilityElement = true
        canvas.accessibilityValue = (layout.attributed.string as NSString).substring(with: NSRange(location: canvas.range.start, length: canvas.range.length))
        view = canvas
    }
}
private final class CoreTextCanvas: UIView {
    var layout: TextLayout!
    var range = PageRange(start: 0, length: 0)
    var padding: Double = 24
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let layout, range.length > 0 else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.textMatrix = .identity
        ctx.translateBy(x: padding, y: bounds.height - 8)
        ctx.scaleBy(x: 1, y: -1)
        let path = CGPath(rect: CGRect(origin: .zero, size: layout.size), transform: nil)
        let frame = CTFramesetterCreateFrame(layout.framesetter, CFRange(location: range.start, length: range.length), path, nil)
        CTFrameDraw(frame, ctx)
    }
}

@MainActor
final class NativeReaderController: UIViewController, ReadingEngine, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {
    private let session: ReaderSession
    private var settings: ReaderSettings
    private var layouts: [Int: TextLayout] = [:]
    private var current = PageAddress(chapter: 0, page: 0)
    private var pager: UIPageViewController?
    private var table: UITableView?
    private struct ScrollRow {
        let chapter: Int
        let chapterID: UUID
        let chunk: ScrollTextChunk
        var id: String { "\(chapterID.uuidString):\(chunk.range.start)" }
    }
    private var scrollRows: [ScrollRow] = []
    private var scrollLayouts: [Int: ScrollChapterLayout] = [:]
    private var rebuilding = false
    private var preparing = Set<Int>()
    private var preloadTasks: [Int: Task<Void, Never>] = [:]
    private var scrollWorldBase: CGFloat = 0
    private var lastDisplay = Date.distantPast
    private var pendingScrollPosition: ReadingPosition?
    private var lastSize = CGSize.zero
    private var loadGeneration = 0
    private var appliedPosition: ReadingPosition
    private var reflowAnchor: ReadingPosition?
    private var acceptsScrollPosition = true
    private var needsResumeBuild = false
    private var resumePosition: ReadingPosition?
    private var programmaticScrolling = false
    private var transitioning = false
    private var coverCurrent: PrintedPage?
    private var coverTarget: PrintedPage?
    private var coverForward = true
    private var coverPan: UIPanGestureRecognizer?
    private var buildTask: Task<Void, Never>?
    #if DEBUG
    private var integrityMutations = 0
    private var integrityFailures = 0
    private var stalePreloads = 0
    private var deferredRebaseForTesting = false
    private var integrityFixtureMode = false
    private var lastIntegritySample = Date.distantPast
    #endif
    #if DEBUG
    private let frameProbe = ReaderFrameProbe()
    #endif

    init(session: ReaderSession, settings: ReaderSettings) {
        self.session = session; self.settings = settings; self.appliedPosition = session.position
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = settings.theme.uiBackground
        session.engine = self
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (controller: NativeReaderController, _: UITraitCollection) in
            if controller.settings.theme == .system { controller.reflow() }
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = self; view.addGestureRecognizer(tap)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        #if DEBUG
        if integrityFixtureMode { return }
        #endif
        guard acceptsScrollPosition, UIApplication.shared.applicationState == .active,
              view.bounds.width > 80, view.bounds.height > 100 else { return }
        if view.bounds.size != lastSize { lastSize = view.bounds.size; reflow() }
    }
    func apply(settings newSettings: ReaderSettings) {
        guard newSettings != settings else { return }
        let previous = settings
        settings = newSettings
        guard acceptsScrollPosition else { needsResumeBuild = true; return }
        if previous.mode == newSettings.mode, previous.hasSameTextLayout(as: newSettings),
           previous.theme == newSettings.theme || newSettings.mode == .scroll {
            view.backgroundColor = settings.theme.uiBackground
            table?.backgroundColor = settings.theme.uiBackground
            table?.visibleCells.compactMap { $0 as? ScrollTextCell }.forEach { $0.applyTheme(settings) }
            #if DEBUG
            recordScrollDiagnostic(event: "theme")
            #endif
            return
        }
        if isViewLoaded, lastSize != .zero { reflow(debounce: true) }
    }
    private func reflow(debounce: Bool = false) {
        let anchor = reflowAnchor ?? pendingScrollPosition ?? session.position
        reflowAnchor = anchor
        rebuild(at: anchor, debounce: debounce)
    }
    private var textSize: CGSize { CGSize(width: max(80, view.bounds.width - CGFloat(settings.sidePadding * 2)), height: max(60, view.bounds.height - 16)) }
    private func clearChildren() {
        table?.delegate = nil; table?.dataSource = nil
        for child in children { child.willMove(toParent: nil); child.view.removeFromSuperview(); child.removeFromParent() }
        table?.removeFromSuperview(); table = nil; pager = nil; coverCurrent = nil; coverTarget = nil
        if let coverPan { view.removeGestureRecognizer(coverPan); self.coverPan = nil }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        #if DEBUG
        frameProbe.stop()
        #endif
    }
    override func viewWillDisappear(_ animated: Bool) {
        if settings.mode == .scroll { saveScrollPosition() }
        var ancestor: UIViewController? = self
        var exiting = false
        while let value = ancestor {
            exiting = exiting || value.isBeingDismissed || value.isMovingFromParent
            ancestor = value.parent
        }
        if session.settingsPreviewActive && !exiting { super.viewWillDisappear(animated); return }
        endReading()
        super.viewWillDisappear(animated)
    }
    func endReading() {
        if settings.mode == .scroll { saveScrollPosition() }
        acceptsScrollPosition = false
        if session.isLoading { needsResumeBuild = true; session.isLoading = false }
        buildTask?.cancel(); buildTask = nil
        preloadTasks.values.forEach { $0.cancel() }; preloadTasks.removeAll(); preparing.removeAll()
        loadGeneration += 1
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        acceptsScrollPosition = true
        if let target = resumePosition {
            resumePosition = nil; needsResumeBuild = false; reflowAnchor = nil; rebuild(at: target)
        } else if needsResumeBuild {
            needsResumeBuild = false; reflow()
        } else { prepareNeighbors() }
        view.setNeedsLayout()
        #if DEBUG
        if let table { frameProbe.attach(to: table) }
        #endif
    }
    private func prepared(_ chapter: Int) async throws -> PreparedReaderChapter {
        let capturedSettings = settings, size = textSize, width = view.bounds.width
        let text = try await session.loadText(at: chapter)
        try Task.checkCancellation()
        let title = session.chapters.indices.contains(chapter) ? session.chapters[chapter].title : nil
        let foreground = settings.theme.uiForeground.resolvedColor(with: traitCollection)
        return try await ReaderLayoutWorker.shared.prepare(text: text, size: size, width: width, settings: capturedSettings, title: title, foreground: foreground)
    }
    private func rebuild(at position: ReadingPosition, debounce: Bool = false) {
        guard session.chapters.indices.contains(position.chapter) else {
            session.error = "阅读位置对应的章节暂不可用，原位置已保留。"; return
        }
        buildTask?.cancel()
        preloadTasks.values.forEach { $0.cancel() }; preloadTasks.removeAll()
        loadGeneration += 1; preparing.removeAll(); let generation = loadGeneration
        let targetChapter = min(max(0, position.chapter), max(0, session.chapters.count - 1))
        session.isLoading = true
        buildTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == loadGeneration { buildTask = nil } }
            do {
                if debounce { try await Task.sleep(nanoseconds: 140_000_000) }
                let chapter = try await prepared(targetChapter)
                var adjacentScroll: [Int: ScrollChapterLayout] = [:]
                if settings.mode == .scroll {
                    for index in (targetChapter - 2)...(targetChapter + 2) where index != targetChapter && session.chapters.indices.contains(index) {
                        if let scroll = try await prepared(index).scroll { adjacentScroll[index] = scroll }
                    }
                }
                guard generation == loadGeneration else { return }
                #if DEBUG
                let visibleLines: Int
                if let pages = chapter.pages, let first = pages.ranges.first {
                    let frame = CTFramesetterCreateFrame(pages.framesetter, CFRange(location: first.start, length: first.length), CGPath(rect: CGRect(origin: .zero, size: pages.size), transform: nil), nil)
                    visibleLines = CFArrayGetCount(CTFrameGetLines(frame))
                } else { visibleLines = chapter.scroll?.chunks.first?.lines.filter { $0.y < self.view.bounds.height - 16 }.count ?? 0 }
                ReaderPerformanceRecorder.shared.recordViewport(width: view.bounds.width, height: view.bounds.height, visibleLines: visibleLines)
                #endif
                rebuilding = true
                clearChildren()
                layouts = chapter.pages.map { [targetChapter: $0] } ?? [:]
                scrollLayouts = chapter.scroll.map { [targetChapter: $0] } ?? [:]
                scrollLayouts.merge(adjacentScroll) { current, _ in current }
                current = PageAddress(chapter: targetChapter, page: chapter.pages?.page(containing: position.characterOffset) ?? 0)
                appliedPosition = position
                pendingScrollPosition = nil
                view.backgroundColor = settings.theme.uiBackground
                if settings.mode == .scroll { try buildScroll() }
                else if settings.mode == .cover { buildCover() }
                else { buildPager() }
                rebuilding = false
                session.isLoading = false
                if settings.mode == .scroll { updateScrollPosition(); saveScrollPosition() }
                else { reportCurrent() }
                prepareNeighbors()
            } catch is CancellationError { }
            catch { guard generation == loadGeneration else { return }; session.isLoading = false; session.error = error.localizedDescription }
        }
    }
    private func prepareNeighbors() {
        let chapter = current.chapter; let generation = loadGeneration
        let neighbors = settings.mode == .scroll ? [chapter - 1, chapter + 1, chapter - 2, chapter + 2] : [chapter - 1, chapter + 1]
        for index in neighbors where session.chapters.indices.contains(index) && !preparing.contains(index) && (settings.mode == .scroll ? scrollLayouts[index] == nil : layouts[index] == nil) {
            preparing.insert(index)
            preloadTasks[index] = Task { [weak self] in
                guard let self else { return }
                defer { if generation == loadGeneration { preparing.remove(index); preloadTasks[index] = nil } }
                do {
                    let chapter = try await prepared(index)
                    guard generation == loadGeneration else {
                        #if DEBUG
                        stalePreloads += 1
                        #endif
                        return
                    }
                    // A preload can finish long after its original viewport left.
                    guard abs(index - self.current.chapter) <= 3 else { return }
                    if let scroll = chapter.scroll {
                        scrollLayouts[index] = scroll
                        synchronizeScrollRows()
                    } else if let pages = chapter.pages {
                        layouts[index] = pages
                        layouts = layouts.filter { abs($0.key - self.current.chapter) <= 1 }
                        refreshPagerNeighbors()
                    }
                } catch { /* Explicit navigation retries and presents a recoverable error. */ }
            }
        }
    }
    private func refreshPagerNeighbors() {
        guard let pager, !transitioning, let visible = pager.viewControllers else { return }
        // UIPageViewController caches a nil data-source answer at a chapter edge.
        // Refresh after asynchronous preload so the next swipe can cross it.
        pager.dataSource = nil; pager.setViewControllers(visible, direction: .forward, animated: false); pager.dataSource = self
    }
    private func printed(_ address: PageAddress) -> PrintedPage? {
        guard let layout = layouts[address.chapter], layout.ranges.indices.contains(address.page) else { return nil }
        return PrintedPage(address: address, layout: layout, settings: settings)
    }
    private func neighbor(of address: PageAddress, forward: Bool) -> PageAddress? {
        guard let layout = layouts[address.chapter] else { return nil }
        if forward {
            if address.page + 1 < layout.ranges.count { return PageAddress(chapter: address.chapter, page: address.page + 1) }
            if layouts[address.chapter + 1] != nil { return PageAddress(chapter: address.chapter + 1, page: 0) }
        } else {
            if address.page > 0 { return PageAddress(chapter: address.chapter, page: address.page - 1) }
            if let previous = layouts[address.chapter - 1] { return PageAddress(chapter: address.chapter - 1, page: previous.ranges.count - 1) }
        }
        return nil
    }
    private func attach(_ child: UIViewController) {
        addChild(child); child.view.frame = view.bounds; child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view); child.didMove(toParent: self)
    }
    private func buildPager() {
        let controller = UIPageViewController(transitionStyle: settings.mode == .curl ? .pageCurl : .scroll, navigationOrientation: .horizontal, options: [.spineLocation: UIPageViewController.SpineLocation.min.rawValue])
        controller.isDoubleSided = false; controller.dataSource = self; controller.delegate = self
        for recognizer in controller.gestureRecognizers where recognizer is UITapGestureRecognizer { recognizer.isEnabled = false }
        controller.view.backgroundColor = settings.theme.uiBackground; pager = controller; attach(controller)
        if let page = printed(current) { controller.setViewControllers([page], direction: .forward, animated: false) }
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? PrintedPage, let address = neighbor(of: page.address, forward: false) else { return nil }; return printed(address)
    }
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? PrintedPage, let address = neighbor(of: page.address, forward: true) else { return nil }; return printed(address)
    }
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) { transitioning = true }
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        transitioning = false
        if completed, let page = pageViewController.viewControllers?.first as? PrintedPage { reflowAnchor = nil; session.menuVisible = false; current = page.address; reportCurrent(); prepareNeighbors() }
    }
    func move(forward: Bool) {
        guard !transitioning else { return }
        reflowAnchor = nil
        session.menuVisible = false
        if settings.mode == .scroll, let table { programmaticScrolling = true; table.setContentOffset(CGPoint(x: 0, y: min(max(-table.adjustedContentInset.top, table.contentOffset.y + (forward ? 1 : -1) * table.bounds.height * 0.85), max(0, table.contentSize.height - table.bounds.height))), animated: true); return }
        guard let target = neighbor(of: current, forward: forward), let page = printed(target) else {
            let chapter = current.chapter + (forward ? 1 : -1)
            guard session.chapters.indices.contains(chapter) else { UIImpactFeedbackGenerator(style: .soft).impactOccurred(); return }
            rebuild(at: ReadingPosition(chapter: chapter, characterOffset: forward ? 0 : max(0, session.chapters[chapter].length - 1))); return
        }
        transitioning = true
        if let pager {
            pager.setViewControllers([page], direction: forward ? .forward : .reverse, animated: true) { [weak self] completed in
                guard let self else { return }; self.transitioning = false
                if completed { self.current = target; self.reportCurrent(); self.prepareNeighbors() }
            }
        } else { startCover(target: page, forward: forward); finishCover(commit: true, duration: 0.24) }
    }
    func navigate(to position: ReadingPosition) {
        reflowAnchor = nil; session.menuVisible = false
        if acceptsScrollPosition { rebuild(at: position) }
        else { resumePosition = position }
    }
    private func reportCurrent() {
        guard let layout = layouts[current.chapter], layout.ranges.indices.contains(current.page) else { return }
        let range = layout.ranges[current.page]
        session.report(ReadingPosition(chapter: current.chapter, characterOffset: range.start, progression: session.progress(chapter: current.chapter, offset: range.start)), pageInfo: "\(current.page + 1) / \(layout.ranges.count)")
    }
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let point = gesture.location(in: view), ratio = point.x / max(1, view.bounds.width)
        if ratio < settings.tapZoneRatio { move(forward: settings.rightHanded) }
        else if ratio > 1 - settings.tapZoneRatio { move(forward: true) }
        else { session.menuVisible.toggle() }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { !transitioning }

    // Cover uses real child views, follows the pan, and commits only after completion.
    private func buildCover() {
        if let page = printed(current) { coverCurrent = page; attach(page) }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(coverDragged(_:)))
        pan.delegate = self; view.addGestureRecognizer(pan); coverPan = pan
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y) && !transitioning
    }
    private func startCover(target: PrintedPage, forward: Bool) {
        coverTarget = target; coverForward = forward; attach(target)
        target.view.layer.shadowColor = UIColor.black.cgColor; target.view.layer.shadowOpacity = 0.18; target.view.layer.shadowRadius = 8
        if forward, let old = coverCurrent { view.bringSubviewToFront(old.view) }
        else { target.view.transform = CGAffineTransform(translationX: -view.bounds.width, y: 0) }
    }
    @objc private func coverDragged(_ pan: UIPanGestureRecognizer) {
        let dx = pan.translation(in: view).x
        switch pan.state {
        case .began:
            let forward = pan.velocity(in: view).x < 0
            guard let target = neighbor(of: current, forward: forward), let page = printed(target) else { return }
            transitioning = true; startCover(target: page, forward: forward)
        case .changed:
            guard coverTarget != nil else { return }
            if coverForward { coverCurrent?.view.transform = CGAffineTransform(translationX: min(0, max(-view.bounds.width, dx)), y: 0) }
            else { coverTarget?.view.transform = CGAffineTransform(translationX: min(0, max(-view.bounds.width, -view.bounds.width + dx)), y: 0) }
        case .ended, .cancelled, .failed:
            guard coverTarget != nil else { return }
            let velocity = pan.velocity(in: view).x
            let commit = pan.state == .ended && (coverForward ? dx < -view.bounds.width * 0.28 || velocity < -550 : dx > view.bounds.width * 0.28 || velocity > 550)
            finishCover(commit: commit, duration: 0.2)
        default: break
        }
    }
    private func finishCover(commit: Bool, duration: Double) {
        guard let target = coverTarget else { transitioning = false; return }
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
            if self.coverForward { self.coverCurrent?.view.transform = commit ? CGAffineTransform(translationX: -self.view.bounds.width, y: 0) : .identity }
            else { target.view.transform = commit ? .identity : CGAffineTransform(translationX: -self.view.bounds.width, y: 0) }
        } completion: { _ in
            let removed = commit ? self.coverCurrent : target
            removed?.willMove(toParent: nil); removed?.view.removeFromSuperview(); removed?.removeFromParent()
            if commit { self.reflowAnchor = nil; self.session.menuVisible = false; self.coverCurrent = target; self.current = target.address; self.reportCurrent(); self.prepareNeighbors() }
            self.coverCurrent?.view.transform = .identity; self.coverTarget = nil; self.transitioning = false
        }
    }

    // Native inertia and bounce are unchanged. Moving windows append only;
    // idle rebases reuse worker-prepared heights and drawings, then restore the
    // same visible character before UIKit commits the next display frame.
    private func buildScroll() throws {
        let table = UITableView(frame: view.bounds, style: .plain)
        table.accessibilityIdentifier = "reader.scrollViewport"
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self; table.delegate = self
        table.separatorStyle = .none; table.backgroundColor = settings.theme.uiBackground
        table.estimatedRowHeight = 0
        table.contentInsetAdjustmentBehavior = .never
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        table.register(ScrollTextCell.self, forCellReuseIdentifier: "paragraph")
        self.table = table
        scrollWorldBase = 0
        let window = ScrollWindow.chapters(available: Set(scrollLayouts.keys), mounted: [], anchor: appliedPosition.chapter, visible: [], deferRebase: false)
        scrollRows = rows(for: window)
        view.addSubview(table)
        table.reloadData() // Initial presentation only; no visible scrolling to interrupt.
        let targetOffset = min(max(0, appliedPosition.characterOffset), max(0, session.chapters[appliedPosition.chapter].length - 1))
        guard let row = scrollRows.firstIndex(where: { $0.chapter == appliedPosition.chapter && $0.chunk.range.end > targetOffset }) else {
            throw ReaderError.message("正文锚点尚未准备好，已保留原阅读位置，请重试本章。")
        }
        do {
            let path = IndexPath(row: row, section: 0)
            table.layoutIfNeeded()
            let chunk = scrollRows[row].chunk
            let localOffset = max(0, targetOffset - chunk.range.start)
            let lineY = chunk.lines.last(where: { $0.start <= localOffset })?.y ?? 0
            let y = table.rectForRow(at: path).minY + lineY - table.contentInset.top
            table.setContentOffset(CGPoint(x: 0, y: min(max(-table.contentInset.top, y), max(-table.contentInset.top, table.contentSize.height - table.bounds.height + table.contentInset.bottom))), animated: false)
        }
        #if DEBUG
        frameProbe.attach(to: table)
        #endif
    }
    private func rows(for chapters: [Int]) -> [ScrollRow] {
        chapters.flatMap { index in
            (scrollLayouts[index]?.chunks ?? []).map { ScrollRow(chapter: index, chapterID: session.chapters[index].id, chunk: $0) }
        }
    }
    private func readingRow(in table: UITableView) -> IndexPath? {
        let y = min(max(0, table.contentOffset.y + table.contentInset.top), max(0, table.contentSize.height - 0.5))
        return table.indexPathForRow(at: CGPoint(x: table.bounds.midX, y: y + 0.25)) ?? table.indexPathsForVisibleRows?.min()
    }
    private func synchronizeScrollRows() {
        guard UIApplication.shared.applicationState == .active, let table, settings.mode == .scroll, !rebuilding,
              let anchorPath = readingRow(in: table), scrollRows.indices.contains(anchorPath.row) else { return }
        ReaderPerformance.measure(.chapterUpdate) {
            let anchor = scrollRows[anchorPath.row]
            let visible = Set((table.indexPathsForVisibleRows ?? []).compactMap { scrollRows.indices.contains($0.row) ? scrollRows[$0.row].chapter : nil })
            let mounted = Array(Set(scrollRows.map(\.chapter))).sorted()
            var deferRebase = table.isTracking || table.isDragging || table.isDecelerating || programmaticScrolling
            #if DEBUG
            deferRebase = deferRebase || deferredRebaseForTesting
            #endif
            let window = ScrollWindow.chapters(available: Set(scrollLayouts.keys), mounted: mounted, anchor: anchor.chapter, visible: visible, deferRebase: deferRebase)
            let next = rows(for: window)
            // Refuse a cache update that cannot preserve the actual visible row.
            guard next.contains(where: { $0.id == anchor.id }) else { return }
            let oldIDs = Set(scrollRows.map(\.id)), nextIDs = Set(next.map(\.id))
            let deleted = scrollRows.enumerated().compactMap { !nextIDs.contains($0.element.id) ? IndexPath(row: $0.offset, section: 0) : nil }
            let inserted = next.enumerated().compactMap { !oldIDs.contains($0.element.id) ? IndexPath(row: $0.offset, section: 0) : nil }
            guard !deleted.isEmpty || !inserted.isEmpty else { return }
            let oldOffset = table.contentOffset.y
            let oldAnchorY = table.rectForRow(at: anchorPath).minY
            rebuilding = true
            if deferRebase {
                // One transaction at a time. Preloads arriving during it are
                // coalesced from scrollLayouts after UIKit finishes this append.
                assert(deleted.isEmpty && next.prefix(scrollRows.count).map(\.id) == scrollRows.map(\.id))
                let generation = loadGeneration
                UIView.performWithoutAnimation {
                    table.performBatchUpdates {
                        scrollRows = next
                        table.insertRows(at: inserted, with: .none)
                    } completion: { [weak self, weak table] _ in
                        guard let self, let table, self.table === table, generation == self.loadGeneration else { return }
                        ReaderPerformance.measure(.chapterUpdate) {
                            rebuilding = false
                            #if DEBUG
                            integrityMutations += 1
                            if let row = scrollRows.firstIndex(where: { $0.id == anchor.id }),
                               abs(table.rectForRow(at: IndexPath(row: row, section: 0)).minY - oldAnchorY) > 0.5 { integrityFailures += 1 }
                            recordScrollDiagnostic(event: "append", inserted: inserted.map(\.row))
                            #endif
                            // The finger/inertia may have advanced while UIKit
                            // completed. Never restore an old moving offset here.
                            updateScrollPosition(); synchronizeScrollRows()
                            if !table.isTracking && !table.isDragging && !table.isDecelerating && !programmaticScrolling { saveScrollPosition() }
                        }
                    }
                }
                return
            }
            // Rebase only at rest. Reuse cached glyphs rather than rebuilding
            // text or relying on UIKit's animated deletion offset bookkeeping.
            UIView.performWithoutAnimation {
                scrollRows = next
                table.reloadData(); table.layoutIfNeeded()
                if let row = scrollRows.firstIndex(where: { $0.id == anchor.id }) {
                    let newAnchorY = table.rectForRow(at: IndexPath(row: row, section: 0)).minY
                    let shift = newAnchorY - oldAnchorY
                    scrollWorldBase -= shift
                    table.setContentOffset(CGPoint(x: 0, y: oldOffset + shift), animated: false)
                    table.layoutIfNeeded()
                }
            }
            rebuilding = false
            // Retain mounted drawings during inertia, and a small preload halo.
            // Idle transactions reclaim rows outside visible +/-2 chapters.
            let mountedSet = Set(window)
            scrollLayouts = scrollLayouts.filter { mountedSet.contains($0.key) || abs($0.key - anchor.chapter) <= 2 }
            #if DEBUG
            integrityMutations += 1
            if deferRebase {
                if let row = scrollRows.firstIndex(where: { $0.id == anchor.id }),
                   abs(table.rectForRow(at: IndexPath(row: row, section: 0)).minY - oldAnchorY) > 0.5 { integrityFailures += 1 }
            } else {
                let after = readingRow(in: table).flatMap { scrollRows.indices.contains($0.row) ? scrollRows[$0.row] : nil }
                let lineBefore = anchor.chunk.character(atY: max(0, oldOffset + table.contentInset.top - oldAnchorY))
                if after?.id != anchor.id { integrityFailures += 1 }
                if let after, let path = readingRow(in: table) {
                    let lineAfter = after.chunk.character(atY: max(0, table.contentOffset.y + table.contentInset.top - table.rectForRow(at: path).minY))
                    if abs(lineBefore - lineAfter) > 3 { integrityFailures += 1 }
                }
            }
            recordScrollDiagnostic(event: "rows", deleted: deleted.map(\.row), inserted: inserted.map(\.row))
            #endif
        }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { scrollRows.count }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { scrollRows[indexPath.row].chunk.height }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "paragraph", for: indexPath) as? ScrollTextCell else { return UITableViewCell() }
        cell.configure(chunk: scrollRows[indexPath.row].chunk, settings: settings)
        return cell
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard acceptsScrollPosition, UIApplication.shared.applicationState == .active,
              scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating || programmaticScrolling else { return }
        ReaderPerformance.measure(.scrollCallback) { updateScrollPosition() }
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        reflowAnchor = nil; session.menuVisible = false
        // Synchronize prepared trailing rows without rebasing the active gesture.
        synchronizeScrollRows()
    }
    private func updateScrollPosition() {
        guard acceptsScrollPosition, !rebuilding, let table else { return }
        // The previous row may overlap only the 8pt paper inset. Anchor the
        // actual reading origin so a chapter start cannot become its predecessor.
        guard let path = readingRow(in: table),
              scrollRows.indices.contains(path.row) else { return }
        let item = scrollRows[path.row]
        let previousChapter = current.chapter
        current = PageAddress(chapter: item.chapter, page: 0)
        let localY = table.contentOffset.y + table.contentInset.top - table.rectForRow(at: path).minY
        let offset = item.chunk.character(atY: max(0, localY))
        let anchor = min(item.chunk.range.end, item.chunk.range.start + offset)
        pendingScrollPosition = ReadingPosition(chapter: item.chapter, characterOffset: anchor, progression: session.progress(chapter: item.chapter, offset: anchor))
        // UI feedback only. No library publishing or JSON writes while moving.
        if Date().timeIntervalSince(lastDisplay) >= 0.5, let pendingScrollPosition {
            session.stage(pendingScrollPosition); lastDisplay = Date()
        }
        if previousChapter != current.chapter || path.row >= scrollRows.count - 3 || path.row < 3 { prepareNeighbors() }
        #if DEBUG
        recordScrollDiagnostic(event: "scroll")
        #endif
    }
    private func saveScrollPosition() {
        guard let pendingScrollPosition else { return }
        session.report(pendingScrollPosition)
        #if DEBUG
        // Stable, text-free position diagnostic for restoration regressions.
        // Updated only at commit boundaries, never for every scrolling frame.
        table?.accessibilityValue = "\(pendingScrollPosition.chapter):\(pendingScrollPosition.characterOffset)"
        recordScrollDiagnostic(event: "commit")
        if ProcessInfo.processInfo.arguments.contains("--uitest-seed") {
            print("ReaderAnchor commit chapter=\(pendingScrollPosition.chapter) offset=\(pendingScrollPosition.characterOffset) y=\(table?.contentOffset.y ?? 0)")
        }
        #endif
    }
    func containsReadingAnchor(_ position: ReadingPosition) -> Bool {
        guard position.locatorJSON == nil, position.chapter == current.chapter else { return false }
        if settings.mode == .scroll {
            if let reflowAnchor, reflowAnchor.chapter == position.chapter, reflowAnchor.characterOffset == position.characterOffset { return true }
            guard let table, let path = readingRow(in: table), scrollRows.indices.contains(path.row) else { return false }
            let row = scrollRows[path.row]
            let y = max(0, table.contentOffset.y + table.contentInset.top - table.rectForRow(at: path).minY)
            let start = row.chunk.character(atY: y)
            let end = row.chunk.lines.first(where: { $0.start > start })?.start ?? row.chunk.range.length
            return position.characterOffset >= row.chunk.range.start + start && position.characterOffset < row.chunk.range.start + end
        }
        guard let layout = layouts[current.chapter], layout.ranges.indices.contains(current.page) else { return false }
        let range = layout.ranges[current.page]
        return position.characterOffset >= range.start && position.characterOffset < range.end
    }
    func flushPosition() {
        // The last delegate anchor remains valid while UIKit dismisses or takes
        // a background snapshot. Teardown geometry must never replace it.
        if settings.mode == .scroll { saveScrollPosition() }
    }
    private func finishScrolling() {
        programmaticScrolling = false
        if acceptsScrollPosition, UIApplication.shared.applicationState == .active {
            synchronizeScrollRows(); updateScrollPosition()
        }
        saveScrollPosition()
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishScrolling() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishScrolling() }
    }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { finishScrolling() }
    #if DEBUG
    private func recordScrollDiagnostic(event: String, deleted: [Int] = [], inserted: [Int] = []) {
        guard ProcessInfo.processInfo.arguments.contains("--reader-integrity") else { return }
        if event == "scroll" && Date().timeIntervalSince(lastIntegritySample) < 0.1 { return }
        lastIntegritySample = Date()
        guard let snapshot = integritySnapshot() else { return }
        var record = snapshot
        record["event"] = event; record["deleted"] = deleted; record["inserted"] = inserted
        if let data = try? JSONSerialization.data(withJSONObject: record, options: .sortedKeys), let text = String(data: data, encoding: .utf8) {
            table?.accessibilityLabel = text
            print("ReaderIntegrity " + text)
        }
    }
    func integritySnapshot() -> [String: Any]? {
        guard let table, let path = readingRow(in: table), scrollRows.indices.contains(path.row),
              let cell = table.cellForRow(at: path) as? ScrollTextCell else { return nil }
        let row = scrollRows[path.row]
        let localY = max(0, table.contentOffset.y + table.contentInset.top - table.rectForRow(at: path).minY)
        let drawn = row.chunk.range.start + cell.character(at: CGPoint(x: settings.sidePadding + 0.1, y: localY + 1))
        let logical = row.chunk.range.start + row.chunk.character(atY: localY)
        let prefix = session.chapters.prefix(row.chapter).reduce(0) { $0 + $1.length }
        let actualText = cell.renderedText
        let marker = actualText.range(of: "样本章节[0-9]+", options: .regularExpression).map { Int(actualText[$0].dropFirst(4)) ?? 0 }
        return ["chapter": row.chapter, "offset": logical, "drawnOffset": drawn,
                "drawnFixtureChapter": marker.map { $0 - 1 } ?? -1,
                "globalOffset": prefix + logical, "rowID": row.id,
                "y": Double(table.contentOffset.y), "worldY": Double(table.contentOffset.y + scrollWorldBase), "size": Double(table.contentSize.height),
                "viewport": Double(table.bounds.height), "generation": loadGeneration,
                "fontSize": Double((row.chunk.attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? 0),
                "fontName": (row.chunk.attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontName ?? "",
                "theme": settings.theme.rawValue,
                "mutations": integrityMutations, "anchorFailures": integrityFailures,
                "staleResultsDiscarded": stalePreloads,
                "mountedChapters": Array(Set(scrollRows.map(\.chapter))).sorted()]
    }
    func installIntegrityFixture(_ layouts: [Int: ScrollChapterLayout], at position: ReadingPosition) throws {
        integrityFixtureMode = true; buildTask?.cancel(); loadGeneration += 1
        loadViewIfNeeded(); view.frame = CGRect(x: 0, y: 0, width: 393, height: 731)
        clearChildren(); scrollLayouts = layouts; appliedPosition = position
        current = PageAddress(chapter: position.chapter, page: 0); rebuilding = true
        try buildScroll(); rebuilding = false; table?.layoutIfNeeded()
    }
    func completeIntegrityPreload(_ layout: ScrollChapterLayout, chapter: Int, generation: Int) {
        guard generation == loadGeneration else { stalePreloads += 1; return }
        scrollLayouts[chapter] = layout; synchronizeScrollRows()
    }
    func setIntegrityViewport(y: CGFloat, deferringRebase: Bool) {
        deferredRebaseForTesting = deferringRebase
        table?.setContentOffset(CGPoint(x: 0, y: y), animated: false); table?.layoutIfNeeded()
        updateScrollPosition(); synchronizeScrollRows()
    }
    var integrityGeneration: Int { loadGeneration }
    #endif
}
