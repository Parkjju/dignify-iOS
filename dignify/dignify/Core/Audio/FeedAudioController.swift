import AVFoundation
import Foundation
import QuartzCore
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

    /// 트랙을 떠날 때 실제 재생된 시간(초)을 알린다. 루프 재생분 누적, 일시정지 구간 제외.
    /// listenThreshold가 실측 체류 분포 한가운데 있어 청취율이 스와이프 속도에 흔들린다 —
    /// 임계값을 어디로 옮길지 보려면 원시 체류 시간이 필요하다. 계측 전용, 서버 기록 없음.
    var onDwell: ((Int, Double) -> Void)?

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
