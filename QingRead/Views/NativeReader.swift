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
        canvas.accessibilityLabel = "正文"
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
        let framesetter = CTFramesetterCreateWithAttributedString(layout.attributed)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: range.start, length: range.length), path, nil)
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
    private var scrollRows: [(chapter: Int, range: PageRange, attributed: NSAttributedString)] = []
    private var rebuilding = false
    private var lastSize = CGSize.zero
    private var loadGeneration = 0
    private var appliedPosition: ReadingPosition
    private var transitioning = false
    private var coverCurrent: PrintedPage?
    private var coverTarget: PrintedPage?
    private var coverForward = true
    private var coverPan: UIPanGestureRecognizer?

    init(session: ReaderSession, settings: ReaderSettings) {
        self.session = session; self.settings = settings; self.appliedPosition = session.position
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = settings.theme.uiBackground
        session.engine = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = self; view.addGestureRecognizer(tap)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 80, view.bounds.height > 100 else { return }
        if view.bounds.size != lastSize { lastSize = view.bounds.size; rebuild(at: session.position) }
    }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle, settings.theme == .system { rebuild(at: session.position) }
    }
    func apply(settings newSettings: ReaderSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        if isViewLoaded, lastSize != .zero { rebuild(at: session.position) }
    }
    private var textSize: CGSize { CGSize(width: max(80, view.bounds.width - CGFloat(settings.sidePadding * 2)), height: max(60, view.bounds.height - 16)) }
    private func clearChildren() {
        for child in children { child.willMove(toParent: nil); child.view.removeFromSuperview(); child.removeFromParent() }
        table?.removeFromSuperview(); table = nil; pager = nil; coverCurrent = nil; coverTarget = nil
        if let coverPan { view.removeGestureRecognizer(coverPan); self.coverPan = nil }
    }
    private func rebuild(at position: ReadingPosition) {
        loadGeneration += 1; let generation = loadGeneration
        let targetChapter = min(max(0, position.chapter), max(0, session.chapters.count - 1))
        session.isLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await session.loadText(at: targetChapter)
                guard generation == loadGeneration else { return }
                let layout = TextPaginator.layout(text, size: textSize, settings: settings)
                layouts = [targetChapter: layout]
                current = PageAddress(chapter: targetChapter, page: layout.page(containing: position.characterOffset))
                appliedPosition = position
                clearChildren(); view.backgroundColor = settings.theme.uiBackground
                if settings.mode == .scroll { buildScroll() }
                else if settings.mode == .cover { buildCover() }
                else { buildPager() }
                session.isLoading = false; reportCurrent(); prepareNeighbors()
            } catch { guard generation == loadGeneration else { return }; session.isLoading = false; session.error = error.localizedDescription }
        }
    }
    private func prepareNeighbors() {
        let chapter = current.chapter; let generation = loadGeneration
        for index in [chapter - 1, chapter + 1] where session.chapters.indices.contains(index) {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let text = try await session.loadText(at: index)
                    guard generation == loadGeneration else { return }
                    layouts[index] = TextPaginator.layout(text, size: textSize, settings: settings)
                    layouts = layouts.filter { abs($0.key - self.current.chapter) <= 1 }
                    if settings.mode == .scroll { appendScrollChapter(index) }
                } catch { /* Explicit navigation retries and presents a recoverable error. */ }
            }
        }
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
        if completed, let page = pageViewController.viewControllers?.first as? PrintedPage { current = page.address; reportCurrent(); prepareNeighbors() }
    }
    func move(forward: Bool) {
        guard !transitioning else { return }
        if settings.mode == .scroll, let table { table.setContentOffset(CGPoint(x: 0, y: min(max(-table.adjustedContentInset.top, table.contentOffset.y + (forward ? 1 : -1) * table.bounds.height * 0.85), max(0, table.contentSize.height - table.bounds.height))), animated: true); return }
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
    func navigate(to position: ReadingPosition) { rebuild(at: position) }
    private func reportCurrent() {
        guard let layout = layouts[current.chapter], layout.ranges.indices.contains(current.page) else { return }
        let range = layout.ranges[current.page]
        let completed = session.chapters.prefix(current.chapter).reduce(0) { $0 + $1.length }
        let total = max(1, session.chapters.reduce(0) { $0 + $1.length })
        session.report(ReadingPosition(chapter: current.chapter, characterOffset: range.start, progression: Double(completed + range.start) / Double(total)), pageInfo: "\(current.page + 1) / \(layout.ranges.count)")
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
            if commit { self.coverCurrent = target; self.current = target.address; self.reportCurrent(); self.prepareNeighbors() }
            self.coverCurrent?.view.transform = .identity; self.coverTarget = nil; self.transitioning = false
        }
    }

    // The table recycles bounded chunks and grows into the adjacent chapter without a page jump.
    private func buildScroll() {
        let table = UITableView(frame: view.bounds, style: .plain)
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]; table.dataSource = self; table.delegate = self
        table.separatorStyle = .none; table.backgroundColor = settings.theme.uiBackground; table.estimatedRowHeight = 600
        table.contentInsetAdjustmentBehavior = .never; table.register(UITableViewCell.self, forCellReuseIdentifier: "paragraph")
        self.table = table; scrollRows = []; appendScrollChapter(current.chapter); view.addSubview(table)
        let row = scrollRows.firstIndex { $0.chapter == current.chapter && $0.range.end > appliedPosition.characterOffset } ?? 0
        if !scrollRows.isEmpty { table.scrollToRow(at: IndexPath(row: row, section: 0), at: .top, animated: false) }
    }
    private func appendScrollChapter(_ index: Int) {
        guard let layout = layouts[index], !scrollRows.contains(where: { $0.chapter == index }), let table else { return }
        let chunks = layout.ranges.map { range in (chapter: index, range: range, attributed: layout.attributed.attributedSubstring(from: NSRange(location: range.start, length: range.length))) }
        // Prepending is deferred until explicit previous-chapter navigation, so a later preload never moves visible text.
        guard scrollRows.isEmpty || index > (scrollRows.last?.chapter ?? -1) else { return }
        scrollRows.append(contentsOf: chunks); table.reloadData()
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { scrollRows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "paragraph", for: indexPath)
        cell.selectionStyle = .none; cell.backgroundColor = settings.theme.uiBackground
        var content = UIListContentConfiguration.cell(); content.attributedText = scrollRows[indexPath.row].attributed
        content.textProperties.numberOfLines = 0; content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: settings.sidePadding, bottom: 8, trailing: settings.sidePadding)
        cell.contentConfiguration = content; return cell
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let table, let row = table.indexPathsForVisibleRows?.first?.row, scrollRows.indices.contains(row) else { return }
        let item = scrollRows[row]
        current = PageAddress(chapter: item.chapter, page: layouts[item.chapter]?.page(containing: item.range.start) ?? 0)
        let offset = table.contentOffset.y - table.rectForRow(at: IndexPath(row: row, section: 0)).minY
        let fraction = min(1, max(0, offset / max(1, table.rectForRow(at: IndexPath(row: row, section: 0)).height)))
        let anchor = item.range.start + Int(fraction * Double(item.range.length))
        let preceding = session.chapters.prefix(item.chapter).reduce(0) { $0 + $1.length }
        let total = max(1, session.chapters.reduce(0) { $0 + $1.length })
        session.report(ReadingPosition(chapter: item.chapter, characterOffset: anchor, progression: Double(preceding + anchor) / Double(total)))
        if row >= scrollRows.count - 3 { prepareNeighbors() }
    }
}
