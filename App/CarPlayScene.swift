#if os(iOS)
import CarPlay
import Combine
import SaptakCore

/// Models are supplied by SaptakApp, including on a CarPlay-only cold launch.
@MainActor enum CarPlaySession {
    private(set) static var library: LibraryModel?
    private(set) static var player: PlayerModel?

    static func configure(library: LibraryModel, player: PlayerModel) {
        self.library = library
        self.player = player
    }
}

@MainActor final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var coordinator: CarPlayCoordinator?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        guard let library = CarPlaySession.library, let player = CarPlaySession.player else { return }
        coordinator = CarPlayCoordinator(library: library, player: player, controller: interfaceController)
        coordinator?.connect()
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        coordinator?.disconnect()
        coordinator = nil
    }

    func sceneDidBecomeActive(_ scene: UIScene) { coordinator?.becameActive() }
    func sceneDidEnterBackground(_ scene: UIScene) { CarPlaySession.player?.checkpoint() }
}

@MainActor private final class CarPlayCoordinator: NSObject, CPSessionConfigurationDelegate {
    private let library: LibraryModel
    private let player: PlayerModel
    private let controller: CPInterfaceController
    private let folders = CPListTemplate(title: "Folders", sections: [])
    private let queue = CPListTemplate(title: "Up Next", sections: [])
    private var catalog = CarPlayCatalog()
    private var queuePage = 0
    private var subscriptions: Set<AnyCancellable> = []
    private var updateTask: Task<Void, Never>?
    private var connected = false
    private var shownError: String?
    private var sessionConfiguration: CPSessionConfiguration?

    init(library: LibraryModel, player: PlayerModel, controller: CPInterfaceController) {
        self.library = library; self.player = player; self.controller = controller
        super.init()
    }

    func connect() {
        connected = true
        sessionConfiguration = CPSessionConfiguration(delegate: self)
        folders.tabTitle = "Folders"
        folders.tabImage = UIImage(systemName: "folder")
        queue.tabTitle = "Up Next"
        queue.tabImage = UIImage(systemName: "list.bullet")
        folders.trailingNavigationBarButtons = [CPBarButton(title: "Refresh") { [weak self] _ in
            self?.library.refresh()
        }]
        let tabs = CPTabBarTemplate(templates: [folders, queue])
        controller.setRootTemplate(tabs, animated: false) { [weak self] success, error in
            if !success { self?.player.error = error?.localizedDescription ?? "CarPlay could not open the library." }
        }
        library.$root.sink { [weak self] _ in self?.scheduleUpdate() }.store(in: &subscriptions)
        library.$isRefreshing.sink { [weak self] _ in self?.scheduleUpdate() }.store(in: &subscriptions)
        library.$error.sink { [weak self] _ in self?.scheduleUpdate() }.store(in: &subscriptions)
        player.$queue.sink { [weak self] _ in self?.scheduleUpdate() }.store(in: &subscriptions)
        player.$isPlaying.sink { [weak self] _ in self?.scheduleUpdate() }.store(in: &subscriptions)
        player.$isLoading.sink { [weak self] _ in self?.scheduleUpdate() }.store(in: &subscriptions)
        player.$error.sink { [weak self] _ in self?.scheduleUpdate() }.store(in: &subscriptions)
        becameActive()
    }

    func becameActive() {
        library.refreshIfNeeded()
        scheduleUpdate()
    }

    func disconnect() {
        connected = false
        updateTask?.cancel()
        updateTask = nil
        subscriptions.removeAll()
        sessionConfiguration?.delegate = nil
        sessionConfiguration = nil
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([])
        player.checkpoint()
    }

    func sessionConfiguration(_ sessionConfiguration: CPSessionConfiguration,
                              limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface) {
        scheduleUpdate()
    }

    private var browsingRestricted: Bool {
        sessionConfiguration?.limitedUserInterfaces.contains(.lists) == true
    }

    private func limitedBrowsingSection() -> CPListSection {
        let row = item("Browsing limited by your vehicle", detail: "Use Now Playing or browse when permitted.",
                       symbol: "play.circle", action: player.queue.current == nil ? nil : { [weak self] in self?.showNowPlaying() })
        return CPListSection(items: [row])
    }

    private func scheduleUpdate() {
        guard connected, updateTask == nil else { return }
        // Published values emit before assignment; render on the next main-actor turn.
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.connected, !Task.isCancelled else { return }
            self.updateTask = nil
            if let root = self.library.root {
                self.player.restoreIfNeeded(root: root, access: self.library.access)
            }
            self.updateFolders()
            self.updateQueue()
            self.updateNowPlaying()
            self.showPlaybackError()
        }
    }

    private func item(_ title: String, detail: String? = nil, symbol: String? = nil,
                      action: (() -> Void)? = nil) -> CPListItem {
        let row = CPListItem(text: title, detailText: detail, image: symbol.flatMap(UIImage.init(systemName:)))
        row.isEnabled = action != nil
        if let action {
            row.handler = { _, completion in
                action()
                // Always release the native selection spinner, including unavailable files.
                completion()
            }
        }
        return row
    }

    private func updateFolders() {
        if browsingRestricted { folders.updateSections([limitedBrowsingSection()]); return }
        guard CPListTemplate.maximumItemCount >= 8 else {
            folders.updateSections([CPListSection(items: [item("Open Saptak on iPhone while parked", detail: "This display limits library browsing.")])])
            return
        }
        guard let root = library.root else {
            folders.updateSections([CPListSection(items: [item(
                library.isRefreshing ? "Loading your audio folder…" : "Choose an audio folder on iPhone",
                detail: library.error == nil ? "Set up Saptak while parked, then return here." : "Folder unavailable. Open Saptak on iPhone while parked.")])])
            return
        }
        let folder = catalog.folder(in: root)
        var rows: [CPListItem] = []
        if let trail = root.ancestry(to: folder.url), trail.count > 1 {
            rows.append(item("Back to \(trail[trail.count - 2].title)", symbol: "chevron.left") { [weak self] in
                guard let self, let root = self.library.root else { return }
                self.catalog.parent(in: root); self.scheduleUpdate()
            })
        }
        if player.queue.current != nil {
            rows.append(item("Now Playing", symbol: "play.circle") { [weak self] in self?.showNowPlaying() })
        }
        if !folder.allTracks.isEmpty {
            rows.append(item("Play all", detail: "Includes subfolders", symbol: "play.fill") { [weak self] in
                self?.play(folder: folder.url)
            })
            rows.append(item("Shuffle all", symbol: "shuffle") { [weak self] in self?.play(folder: folder.url, shuffled: true) })
        }
        let page = CarPlayPage(CarPlayCatalog.entries(in: folder), requested: catalog.page,
                               capacity: CPListTemplate.maximumItemCount - 6)
        for entry in page.items {
            switch entry {
            case .folder(let child):
                let row = item(child.title, detail: "\(child.allTracks.count) tracks", symbol: "folder") { [weak self] in
                    guard let self, let root = self.library.root else { return }
                    self.catalog.browse(child.url, in: root); self.scheduleUpdate()
                }
                row.accessoryType = .disclosureIndicator
                rows.append(row)
            case .track(let track):
                let row = item(track.title, symbol: "music.note") { [weak self] in
                    self?.play(folder: folder.url, track: track)
                }
                row.isPlaying = player.queue.current == track
                rows.append(row)
            }
        }
        if page.hasPrevious { rows.append(item("Previous page", symbol: "chevron.left") { [weak self] in
            self?.catalog.showPage(page.index - 1); self?.scheduleUpdate()
        }) }
        if page.hasNext { rows.append(item("More folders and tracks", symbol: "chevron.right") { [weak self] in
            self?.catalog.showPage(page.index + 1); self?.scheduleUpdate()
        }) }
        if rows.isEmpty { rows.append(item("No audio in this folder")) }
        let detail = library.error == nil ? "\(folder.allTracks.count) tracks · includes subfolders" : "Folder refresh unavailable · showing saved listing"
        folders.updateSections([CPListSection(items: rows, header: folder.title, headerSubtitle: detail, headerImage: nil, headerButton: nil, sectionIndexTitle: nil)])
    }

    private func play(folder url: URL, track: AudioTrack? = nil, shuffled: Bool = false) {
        guard let folder = library.root?.folder(at: url), !folder.allTracks.isEmpty else {
            player.error = "This track or folder is no longer available. Refresh Saptak on iPhone while parked."
            return
        }
        if let track, !folder.allTracks.contains(track) {
            player.error = "This track is no longer available. Refresh Saptak on iPhone while parked."
            return
        }
        player.play(folder.allTracks, access: library.access, shuffled: shuffled, startingAt: track)
        showNowPlaying()
    }

    private func updateQueue() {
        if browsingRestricted { queue.updateSections([limitedBrowsingSection()]); return }
        let tracks = player.queue.tracks
        let page = CarPlayPage(tracks, requested: queuePage, capacity: max(0, CPListTemplate.maximumItemCount - 2))
        queuePage = page.index
        var rows = page.items.map { track in
            let current = player.queue.current == track
            let row = item(track.title, detail: current ? (player.isLoading ? "Loading…" : player.isPlaying ? "Now playing" : "Paused") : track.url.deletingLastPathComponent().lastPathComponent,
                           symbol: current ? "speaker.wave.2" : "music.note") { [weak self] in
                guard let self else { return }
                guard let index = CarPlayCatalog.queueIndex(for: track, in: self.player.queue.tracks) else {
                    self.scheduleUpdate(); return
                }
                if self.player.queue.current != track { self.player.select(index) }
                self.showNowPlaying()
            }
            row.isPlaying = current
            return row
        }
        if page.hasPrevious { rows.append(item("Previous page") { [weak self] in self?.queuePage = page.index - 1; self?.scheduleUpdate() }) }
        if page.hasNext { rows.append(item("More tracks") { [weak self] in self?.queuePage = page.index + 1; self?.scheduleUpdate() }) }
        if rows.isEmpty { rows.append(item("Nothing queued", detail: "Choose a track or Play all in Folders.")) }
        queue.updateSections([CPListSection(items: rows)])
    }

    private func showNowPlaying() {
        guard player.queue.current != nil, controller.topTemplate !== CPNowPlayingTemplate.shared else { return }
        controller.pushTemplate(CPNowPlayingTemplate.shared, animated: true) { [weak self] success, error in
            if !success { self?.player.error = error?.localizedDescription ?? "CarPlay could not open Now Playing." }
        }
    }

    private func updateNowPlaying() {
        let shuffle = CPNowPlayingShuffleButton { [weak self] _ in self?.player.toggleShuffle() }
        let repeatButton = CPNowPlayingRepeatButton { [weak self] _ in self?.player.cycleRepeat() }
        shuffle.isEnabled = !player.queue.tracks.isEmpty
        repeatButton.isEnabled = !player.queue.tracks.isEmpty
        CPNowPlayingTemplate.shared.updateNowPlayingButtons([shuffle, repeatButton])
    }

    private func showPlaybackError() {
        guard let error = player.error else { shownError = nil; return }
        guard error != shownError, controller.presentedTemplate == nil else { return }
        shownError = error
        let dismiss = CPAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.controller.dismissTemplate(animated: true, completion: nil)
            self?.player.error = nil
        }
        controller.presentTemplate(CPAlertTemplate(titleVariants: ["Unable to play this track", error], actions: [dismiss]), animated: true, completion: nil)
    }
}
#endif
