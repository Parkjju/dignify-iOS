import Foundation

/// SwiftUI 프리뷰용 장르 목록. 백엔드 없이 온보딩 화면을 띄우려고 둔다.
/// 실제 프로덕션에 활성 트랙이 있는 11개 장르(2026-07-27 기준)와 같은 구성이라
/// 퀴즈 추천 매칭까지 프리뷰에서 그대로 확인된다.
///
/// ponytail: `#if DEBUG`로 감싸지 않았다. `#Preview` 매크로 확장은 DEBUG 가드가 없어
/// Release 아카이브에서도 컴파일되고, 그때 이 심볼이 없으면 빌드가 깨진다.
extension Genre {
    static let previewList: [Genre] = [
        "Hip-Hop/Rap", "Rock", "Pop", "Jazz", "Dance", "Country",
        "R&B/Soul", "Electronic", "K-Pop", "Latin", "CCM",
    ].enumerated().map { Genre(id: $0.offset + 1, name: $0.element, nameEn: $0.element) }
}
