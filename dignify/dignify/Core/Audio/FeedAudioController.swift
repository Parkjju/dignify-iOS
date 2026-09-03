import ActivityKit
import AVFoundation
import Foundation
import MediaPlayer
import QuartzCore
import Observation
import UIKit

/// current-1 / current / current+1 세 트랙만 AVPlayer로 유지하는 슬라이딩 윈도우.
/// current 하나만 재생하고 인접 트랙은 버퍼링만 시켜, 스와이프 즉시 소리가 나게 한다.
/// 윈도우 밖 트랙은 인스턴스를 해제한다(메타데이터는 FeedView가 들고 있음).
@MainActor
@Observable
final class FeedAudioController {
    /// current 트랙의 일시정지 여부 — 재생 상태의 단일 소스.
    /// 탭 토글·인터럽션·백그라운드·트랙 전환 모두 이 값을 갱신하고, 뷰는 이것만 읽는다.
    private(set) var isPaused = false

    /// listenThreshold 이상 재생된 트랙을 트랙당 한 번 알린다.
    /// 서버 기록은 뷰가 한다 — 이 컨트롤러는 네트워크를 모른다.
    /// (설정하지 않으면 아무것도 발사되지 않는다: 마이페이지 미리듣기는 집계 대상이 아님.)
    var onListen: ((Int) -> Void)?

    /// 트랙을 떠날 때 실제 재생된 시간(초)을 알린다. 루프 재생분 누적, 일시정지 구간 제외.
    /// listenThreshold가 실측 체류 분포 한가운데 있어 청취율이 스와이프 속도에 흔들린다 —
    /// 임계값을 어디로 옮길지 보려면 원시 체류 시간이 필요하다. 계측 전용, 서버 기록 없음.
    var onDwell: ((Int, Double) -> Void)?

    /// 잠금화면·이어폰의 다음/이전 트랙 명령이 옮겨갈 인덱스를 알린다.
    /// 피드 인덱스는 뷰가 들고 있어서 실제 이동은 뷰가 한다.
    /// **백그라운드에선 SwiftUI가 body를 다시 평가하지 않아 `.onChange(of:)`가 안 터진다** —
    /// 구현부는 인덱스 변경과 `updateWindow`를 모두 명시적으로 호출해야 한다.
    var onRemoteSeek: ((Int) -> Void)?

    /// 현재 트랙의 체류 시간에 백그라운드 재생분이 섞였는가.
    /// 발사 시점의 scenePhase로 판정하면 백그라운드에서 10분 듣고 복귀해 스와이프한 경우를
    /// 포그라운드 체류로 잘못 기록한다 — 그래서 백그라운드 진입 시점에 표시해 둔다.
    /// 체류 분포는 `listenThreshold`를 어디로 옮길지 보려고 재는 값이라(중앙값 2.0초)
    /// 주머니 속 재생이 섞이면 분포가 망가진다.
    private(set) var dwellHadBackground = false

    /// 지금 앱이 백그라운드인가. 계측 이벤트가 백그라운드 발생분을 표시하는 데 쓴다.
    /// 뷰의 `scenePhase`를 쓰지 않는 이유: `@Environment`는 body 밖에서 읽으면 값이
    /// 얼어붙는데, 계측 콜백은 `onAppear`가 등록한 클로저 안에서 돈다.
    private(set) var isBackground = false

    /// play() 호출부터 재생 위치가 실제로 흐르기 시작할 때까지의 지연(초)을 트랙당 한 번 알린다.
    /// 실측 체류 중앙값이 2.0초라, 소리가 늦게 나오면 유저는 무음만 보고 넘긴다 —
    /// 그 무음 구간이 몇 초인지 지금까지 잰 적이 없다. 계측 전용, 서버 기록 없음.
    /// 스와이프가 지연보다 빨랐으면 아예 발사되지 않는다(= track_viewed만 있고 이 이벤트는 없음).
    var onPlaybackStart: ((Int, Double) -> Void)?

    /// onListen을 이미 보낸 트랙 — 루프·재진입으로 중복 발사하지 않게 한다.
    private var listenedTrackIds: Set<Int> = []

    /// setCurrent에서 play()를 부른 시각. 첫 유효 틱에서 지연을 계산하고 nil로 내린다.
    private var playRequestedAt: CFTimeInterval?

    private var dwellLoops: Double = 0        // 루프로 0에 되돌아간 만큼의 누적
    private var dwellPosition: Double = 0     // 현재 루프에서의 재생 위치

    // ponytail: 훑고 지나간 스와이프와 실제 청취를 가르는 값 하나.
    // 실데이터 보고 조정. 프리뷰가 30초라 상한은 그쪽.
    private let listenThreshold: Double = 5

    /// Now Playing 표시와 다음/이전 가능 여부 판정에 쓴다. `updateWindow`가 매번 갱신한다.
    private var windowFeeds: [Feed] = []
    private var windowIndex = 0

    /// 백그라운드에서 계속 재생할 세션인가. 피드 디깅만 해당한다 —
    /// 마이페이지·픽 작성의 단발 미리듣기는 앱을 벗어나면 멈춘다.
    private var isFeedSession = false

    /// 백그라운드 디깅 중에만 살아 있는 Live Activity. 하입 버튼 하나가 존재 이유다.
    private var activity: Activity<DiggingActivityAttributes>?

    /// 잠금화면에 올린 아트워크. 트랙당 한 번만 받고 다음 트랙에서 버린다.
    private var artworkTrackId: Int?
    private var artwork: MPMediaItemArtwork?

    private var players: [Int: AVPlayer] = [:]              // trackId → player
    private var loopObservers: [Int: NSObjectProtocol] = [:]
    private var currentTrackId: Int?

    private var timeObserver: Any?
    private var timeObserverPlayer: AVPlayer?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    private let fadeIn: Double = 1.0
    private let fadeOut: Double = 2.0

    init() {
        // 무음 스위치와 무관하게 들리도록(음악 감상 앱 기대). 한 번만 설정.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        observeInterruptions()
        observeBackground()
    }

    /// 현재 재생(또는 일시정지) 중인 트랙 id — 마이페이지 셀의 재생 오버레이 판단용.
    var activeTrackId: Int? { currentTrackId }

    /// 단발 미리듣기(마이페이지). 같은 트랙이면 재생↔정지 토글, 다른 트랙이면 교체 후 재생.
    /// 윈도우 관리 없이 한 번에 한 트랙만 유지한다.
    func togglePreview(trackId: Int, url: URL) {
        if currentTrackId == trackId {
            toggleCurrentPlayback()
            return
        }
        for id in Array(players.keys) { teardown(id) }
        removeTimeObserver()
        currentTrackId = nil                 // setCurrent의 동일 트랙 가드를 통과시킨다.
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        player.volume = 0
        players[trackId] = player
        addLoop(for: trackId, player: player)
        isFeedSession = false                // 미리듣기는 백그라운드로 이어지지 않는다.
        windowFeeds = []
        claimRemoteCommands()
        setCurrent(trackId)
        updateNowPlaying()
    }

    // MARK: - Window

    /// 스와이프 settle 후(= currentIndex 변경 후) 호출. current 기준 3칸 윈도우를 재구성한다.
    func updateWindow(feeds: [Feed], current: Int) {
        guard feeds.indices.contains(current) else { stop(); return }

        // 유지할 트랙: current-1 / current / current+1 중 previewUrl이 유효한 것만.
        var keep: [Int: URL] = [:]
        for offset in -1...1 {
            let i = current + offset
            guard feeds.indices.contains(i),
                  let url = URL(string: feeds[i].previewUrl) else { continue }
            keep[feeds[i].trackId] = url
        }

        // 윈도우 밖 플레이어 해제.
        for id in Array(players.keys) where keep[id] == nil {
            teardown(id)
        }

        // 윈도우 안 신규 트랙 플레이어 생성 — 이 시점부터 버퍼링 시작, 재생은 정지 상태.
        for (id, url) in keep where players[id] == nil {
            let player = AVPlayer(url: url)
            player.actionAtItemEnd = .none   // 종료 후 정지 → 루프는 아래 옵저버가 처리
            player.volume = 0
            players[id] = player
            addLoop(for: id, player: player)
        }

        windowFeeds = feeds
        windowIndex = current
        isFeedSession = true
        claimRemoteCommands()
        setCurrent(feeds[current].trackId)
        updateNowPlaying()
    }

    /// 현재 재생 트랙을 전환한다. 같은 트랙이면 재시작하지 않는다.
    private func setCurrent(_ trackId: Int) {
        guard trackId != currentTrackId else { return }

        if let old = currentTrackId, let p = players[old] {
            p.pause()
            p.seek(to: .zero)
        }
        removeTimeObserver()

        currentTrackId = trackId
        guard let player = players[trackId] else { return }
        player.seek(to: .zero)
        player.volume = 0                    // fade in은 time observer가 올린다
        markPlayRequested()
        player.play()
        isPaused = false                     // 새 current는 항상 재생 상태로 시작
        addTimeObserver(for: player, trackId: trackId)
    }

    // MARK: - Loop & fade

    private func addLoop(for id: Int, player: AVPlayer) {
        // current 트랙만 끝까지 재생되므로 무한 루프도 current에서만 발생한다.
        let obs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.handleTrackEnd(id: id) { return }
                player.seek(to: .zero)
                player.play()                // fade in은 time observer가 다시 올린다
                self.updateNowPlaying()      // 위치가 0으로 돌아갔다 — 잠금화면 스크러버도 되돌린다.
            }
        }
        loopObservers[id] = obs
    }

    /// 트랙이 끝까지 갔다. 넘겼으면 true, 그대로 루프해야 하면 false.
    ///
    /// **화면에서는 루프한다** — 스와이프로 언제든 넘길 수 있으니, 판단하는 동안 계속 들리는 게 맞다.
    /// **백그라운드에서는 넘긴다** — 스와이프가 없어서 안 넘기면 같은 30초가 무한 반복된다.
    /// 프리뷰를 무한 루프시키지 않는 쪽이 iTunes 약관에도 안전하다.
    ///
    /// 피드 끝이면 `.noSuchContent`가 와서 루프로 떨어진다. 페이지네이션이 붙으면 다시 넘어간다.
    @discardableResult
    func handleTrackEnd(id: Int) -> Bool {
        // 윈도우 안 다른 플레이어는 재생하지 않아 여기 오지 않지만, 와도 현재 트랙만 넘긴다.
        guard currentTrackId == id, isBackground else { return false }
        return remoteSeek(by: 1) == .success
    }

    private func addTimeObserver(for player: AVPlayer, trackId: Int) {
        timeObserverPlayer = player
        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let item = player.currentItem else { return }
                let duration = item.duration.seconds
                guard duration.isFinite, duration > 0 else { return }
                player.volume = Float(Self.fadeVolume(
                    at: time.seconds, duration: duration, fadeIn: self.fadeIn, fadeOut: self.fadeOut))
                self.reportPlaybackStartIfNeeded(trackId: trackId, position: time.seconds)
                self.recordListenIfNeeded(trackId: trackId, playedFor: time.seconds)
                self.advanceDwell(to: time.seconds)
            }
        }
    }

    /// play() 직전에 호출해 지연 측정을 연다. setCurrent가 부르고, 테스트가 부른다.
    func markPlayRequested() {
        playRequestedAt = CACurrentMediaTime()
    }

    /// 재생 위치가 0에서 처음 벗어난 순간 = 실제로 소리가 나기 시작한 시점.
    /// 버퍼링 중에는 play()를 불러도 위치가 0에 머무르므로, 이 델타가 곧 무음 구간이다.
    /// ponytail: 이미 도는 time observer에 얹는다. AVPlayer 상태 KVO를 따로 붙이지 않음.
    func reportPlaybackStartIfNeeded(trackId: Int, position: Double) {
        guard let requestedAt = playRequestedAt, position > 0 else { return }
        playRequestedAt = nil
        onPlaybackStart?(trackId, CACurrentMediaTime() - requestedAt)
    }

    /// 재생 위치가 임계값을 넘으면 트랙당 한 번만 onListen을 호출한다.
    /// 시크 UI가 없어 재생 위치 = 실제 들은 시간이고, 일시정지 중엔 옵저버가 안 돈다.
    /// 루프로 위치가 0으로 돌아가도 listenedTrackIds가 재발사를 막는다.
    func recordListenIfNeeded(trackId: Int, playedFor seconds: Double) {
        guard seconds >= listenThreshold, !listenedTrackIds.contains(trackId) else { return }
        listenedTrackIds.insert(trackId)
        onListen?(trackId)
    }

    /// 재생 위치로 체류 시간을 누적한다. 루프로 위치가 되돌아가면 직전 위치를 더한다.
    func advanceDwell(to seconds: Double) {
        if seconds < dwellPosition { dwellLoops += dwellPosition }
        dwellPosition = seconds
    }

    /// 현재 트랙의 누적 체류를 발사하고 카운터를 리셋한다. 트랙 전환·정지에서만 호출.
    /// ponytail: 앱이 강제 종료되면 마지막 트랙 체류는 유실된다. 표본이 아쉬우면 백그라운드 진입에서도 flush.
    func flushDwell() {
        let total = dwellLoops + dwellPosition
        dwellLoops = 0
        dwellPosition = 0
        defer { dwellHadBackground = false }
        guard let id = currentTrackId, total > 0 else { return }
        onDwell?(id, total)
    }

    /// 종료 fadeOut초 전부터 1→0, 시작 fadeIn초 동안 0→1. 그 외 1.0.
    nonisolated static func fadeVolume(at t: Double, duration: Double, fadeIn: Double, fadeOut: Double) -> Double {
        if t < fadeIn { return max(0, t / fadeIn) }
        let remaining = duration - t
        if remaining < fadeOut { return max(0, remaining / fadeOut) }
        return 1
    }

    // MARK: - Interruptions (스펙: 인터럽션 발생 시 일시정지, 자동 재개 없음)

    private func observeInterruptions() {
        let nc = NotificationCenter.default
        interruptionObserver = nc.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                self?.pauseCurrent()
            }
        }
        routeObserver = nc.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                // 이어폰/헤드폰 탈거(oldDeviceUnavailable)만 일시정지 트리거.
                guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
                self?.pauseCurrent()
            }
        }
    }

    // MARK: - Lifecycle (탭 전환 / 백그라운드)

    func pauseCurrent() {
        guard let id = currentTrackId else { return }
        players[id]?.pause()
        isPaused = true
        updateNowPlaying()
    }

    func resumeCurrent() {
        guard let id = currentTrackId else { return }
        players[id]?.play()
        isPaused = false
        updateNowPlaying()
    }

    /// 현재 트랙 재생↔일시정지 토글.
    func toggleCurrentPlayback() {
        isPaused ? resumeCurrent() : pauseCurrent()
    }

    /// 탭 이탈 시 전체 해제. 재진입 시 updateWindow로 다시 세운다.
    func stop() {
        removeTimeObserver()
        for id in Array(players.keys) { teardown(id) }
        currentTrackId = nil
        isPaused = false
        windowFeeds = []
        isFeedSession = false
        updateNowPlaying()               // 재생이 없으면 잠금화면에서도 내린다.
        endActivity()
    }

    // MARK: - 백그라운드 재생

    /// 피드 디깅은 앱을 벗어나도 계속 재생한다(`UIBackgroundModes: audio`).
    /// 뷰의 scenePhase가 아니라 여기서 판단하는 이유: 어느 탭에 있든 정확해야 하는데
    /// TabView에서 뷰 생명주기는 신뢰할 수 없다(`FeedView`가 같은 이유로 탭을 직접 본다).
    private func observeBackground() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enterBackground() }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enterForeground() }
        }
    }

    func enterBackground() {
        isBackground = true
        // 미리듣기는 화면을 떠나면 멈춘다. 피드 디깅만 이어진다.
        guard isFeedSession else { pauseCurrent(); return }
        dwellHadBackground = true
        startActivity()
    }

    func enterForeground() {
        isBackground = false     // dwellHadBackground는 flush까지 남는다.
        endActivity()            // 앱을 열었으면 화면에서 하입하면 된다.
    }

    // MARK: - Live Activity

    /// 하입 상태가 밖에서 바뀌면(화면 탭이든 Live Activity 버튼이든) 잠금화면 표시도 따라간다.
    /// `windowFeeds`는 `updateWindow`가 준 사본이라 뷰가 알려주지 않으면 낡은 채로 남는다.
    func syncHype(trackId: Int, isHyped: Bool) {
        guard let i = windowFeeds.firstIndex(where: { $0.trackId == trackId }),
              windowFeeds[i].isHyped != isHyped else { return }
        windowFeeds[i].isHyped = isHyped
        updateActivity()
    }

    private var activityState: DiggingActivityAttributes.ContentState? {
        guard isFeedSession, windowFeeds.indices.contains(windowIndex) else { return nil }
        let feed = windowFeeds[windowIndex]
        return .init(trackId: feed.trackId, trackName: feed.trackName,
                     artistName: feed.artistName, isHyped: feed.isHyped)
    }

    private func startActivity() {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled,
              let state = activityState else { return }
        activity = try? Activity.request(attributes: DiggingActivityAttributes(),
                                         content: .init(state: state, staleDate: nil))
    }

    /// 백그라운드가 아니면 Activity 자체가 없어 조용히 빠진다 — 호출부가 분기하지 않아도 된다.
    private func updateActivity() {
        guard let activity, let state = activityState else { return }
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    private func endActivity() {
        guard let activity else { return }
        self.activity = nil      // end는 비동기라 먼저 끊어야 중복 호출이 안 쌓인다.
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - 잠금화면 / 이어폰

    /// 지금 잠금화면 커맨드를 쥐고 있는 컨트롤러.
    /// `MPRemoteCommandCenter`는 프로세스에 하나뿐인데 픽 재생이 fullScreenCover라
    /// `FeedView`(=컨트롤러)가 두 개 살아 있는 순간이 있다. 등록만 하면 핸들러가 쌓여서
    /// 커버를 닫은 뒤에도 죽은 컨트롤러가 다음/이전 명령을 먹는다.
    private static weak var commandOwner: FeedAudioController?

    /// 커맨드를 등록하면 잠금화면·제어센터·이어폰·차량·Apple Watch가 한꺼번에 붙는다.
    /// 재생을 시작하는 쪽이 소유권을 가져간다 — 매 스와이프마다 불려도 첫 줄에서 빠져나간다.
    ///
    /// **쓰지 않는 커맨드는 명시적으로 끈다** — `skipForward`가 켜져 있으면 잠금화면에
    /// 다음/이전 대신 +15초 버튼이 뜬다(팟캐스트 UI가 된다).
    private func claimRemoteCommands() {
        guard Self.commandOwner !== self else { return }
        Self.commandOwner = self
        let center = MPRemoteCommandCenter.shared()
        let owned: [MPRemoteCommand] = [
            center.playCommand, center.pauseCommand,
            center.nextTrackCommand, center.previousTrackCommand,
        ]
        for command in owned { command.removeTarget(nil) }   // 직전 소유자의 핸들러를 걷어낸다.
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { () -> MPRemoteCommandHandlerStatus in
                guard let self, self.currentTrackId != nil else { return .noSuchContent }
                self.resumeCurrent()
                return .success
            }
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { () -> MPRemoteCommandHandlerStatus in
                guard let self, self.currentTrackId != nil else { return .noSuchContent }
                self.pauseCurrent()
                return .success
            }
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.remoteSeek(by: 1) ?? .noSuchContent }
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.remoteSeek(by: -1) ?? .noSuchContent }
        }
        // 시크 UI가 없는 앱이다. 30초 프리뷰에 +15초 버튼은 의미도 없다.
        let unused: [MPRemoteCommand] = [
            center.skipForwardCommand, center.skipBackwardCommand,
            center.seekForwardCommand, center.seekBackwardCommand,
            center.changePlaybackPositionCommand,
        ]
        for command in unused { command.isEnabled = false }
    }

    /// 갈 곳이 없으면 `.noSuchContent`를 돌려준다 — 그래야 iOS가 버튼을 헛돌리지 않는다.
    private func remoteSeek(by delta: Int) -> MPRemoteCommandHandlerStatus {
        let target = windowIndex + delta
        guard isFeedSession, windowFeeds.indices.contains(target) else { return .noSuchContent }
        onRemoteSeek?(target)
        return .success
    }

    /// 잠금화면·제어센터 표시. 미리듣기 세션이거나 재생이 없으면 내린다.
    private func updateNowPlaying() {
        guard isFeedSession, windowFeeds.indices.contains(windowIndex) else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let feed = windowFeeds[windowIndex]
        let player = players[feed.trackId]
        // 아이템이 아직 안 열렸으면 duration이 NaN이다. iTunes 프리뷰는 30초라 그걸 쓴다.
        let duration = player?.currentItem?.duration.seconds ?? .nan
        let elapsed = player?.currentTime().seconds ?? .nan
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: feed.trackName,
            MPMediaItemPropertyArtist: feed.artistName,
            MPMediaItemPropertyPlaybackDuration: duration.isFinite ? duration : 30,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed.isFinite ? elapsed : 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
        if let artwork, artworkTrackId == feed.trackId {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkIfNeeded(for: feed)
        updateActivity()
    }

    /// 피드가 이미 600px로 프리페치해 둬서 대개 URLCache 히트다(`RemoteImage`와 같은 경로).
    /// 받아온 뒤 `updateNowPlaying`을 다시 부르지만, 그때는 이 함수가 첫 줄에서 빠져나가 재귀하지 않는다.
    private func loadArtworkIfNeeded(for feed: Feed) {
        guard artworkTrackId != feed.trackId, let url = feed.artworkURL(size: 600) else { return }
        artworkTrackId = feed.trackId
        artwork = nil
        Task { [weak self] in
            let request = URLRequest(url: url)
            var data = URLCache.shared.cachedResponse(for: request)?.data
            if data == nil { data = try? await URLSession.shared.data(for: request).0 }
            guard let data, let image = UIImage(data: data) else { return }
            guard let self, self.artworkTrackId == feed.trackId else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.updateNowPlaying()
        }
    }

    // MARK: - Teardown

    private func teardown(_ id: Int) {
        players[id]?.pause()
        if let obs = loopObservers[id] { NotificationCenter.default.removeObserver(obs) }
        loopObservers[id] = nil
        if currentTrackId == id { removeTimeObserver() }
        players[id] = nil
    }

    /// 트랙 전환·정지·해제가 전부 이 지점을 지나므로 체류 flush도 여기서 한다.
    private func removeTimeObserver() {
        flushDwell()
        if let obs = timeObserver, let p = timeObserverPlayer {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
        timeObserverPlayer = nil
    }
}
