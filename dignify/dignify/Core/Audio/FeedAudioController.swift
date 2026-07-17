import AVFoundation
import Foundation
import Observation

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

    /// onListen을 이미 보낸 트랙 — 루프·재진입으로 중복 발사하지 않게 한다.
    private var listenedTrackIds: Set<Int> = []

    // ponytail: 훑고 지나간 스와이프와 실제 청취를 가르는 값 하나.
    // 실데이터 보고 조정. 프리뷰가 30초라 상한은 그쪽.
    private let listenThreshold: Double = 5

    private var players: [Int: AVPlayer] = [:]              // trackId → player
    private var loopObservers: [Int: NSObjectProtocol] = [:]
    private var currentTrackId: Int?

    private var timeObserver: Any?
    private var timeObserverPlayer: AVPlayer?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?

    private let fadeIn: Double = 1.0
    private let fadeOut: Double = 2.0

    init() {
        // 무음 스위치와 무관하게 들리도록(음악 감상 앱 기대). 한 번만 설정.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        observeInterruptions()
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
        setCurrent(trackId)
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

        setCurrent(feeds[current].trackId)
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
        ) { _ in
            MainActor.assumeIsolated {
                player.seek(to: .zero)
                player.play()                // fade in은 time observer가 다시 올린다
            }
        }
        loopObservers[id] = obs
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
                self.recordListenIfNeeded(trackId: trackId, playedFor: time.seconds)
            }
        }
    }

    /// 재생 위치가 임계값을 넘으면 트랙당 한 번만 onListen을 호출한다.
    /// 시크 UI가 없어 재생 위치 = 실제 들은 시간이고, 일시정지 중엔 옵저버가 안 돈다.
    /// 루프로 위치가 0으로 돌아가도 listenedTrackIds가 재발사를 막는다.
    func recordListenIfNeeded(trackId: Int, playedFor seconds: Double) {
        guard seconds >= listenThreshold, !listenedTrackIds.contains(trackId) else { return }
        listenedTrackIds.insert(trackId)
        onListen?(trackId)
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
    }

    func resumeCurrent() {
        guard let id = currentTrackId else { return }
        players[id]?.play()
        isPaused = false
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
    }

    // MARK: - Teardown

    private func teardown(_ id: Int) {
        players[id]?.pause()
        if let obs = loopObservers[id] { NotificationCenter.default.removeObserver(obs) }
        loopObservers[id] = nil
        if currentTrackId == id { removeTimeObserver() }
        players[id] = nil
    }

    private func removeTimeObserver() {
        if let obs = timeObserver, let p = timeObserverPlayer {
            p.removeTimeObserver(obs)
        }
        timeObserver = nil
        timeObserverPlayer = nil
    }
}
