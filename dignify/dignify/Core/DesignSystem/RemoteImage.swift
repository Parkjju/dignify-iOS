import SwiftUI
import UIKit

/// AsyncImage 대체. 피드의 스와이프 페이징(슬롯 offset 애니메이션) 안에서 AsyncImage가
/// 로드 완료 후에도 placeholder에 멈춰 이미지를 부착하지 않는 문제가 있어, URLSession으로
/// 직접 받아 @State에 담아 확실히 리렌더한다. 프리페치로 데운 URLCache를 먼저 조회해
/// 캐시 히트는 즉시 뜨고(placeholder 깜빡임 없음), 미스만 네트워크로 받는다.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                placeholder()
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }
        let request = URLRequest(url: url)
        if let cached = URLCache.shared.cachedResponse(for: request),
           let img = UIImage(data: cached.data) {
            image = img
            return
        }
        image = nil
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let img = UIImage(data: data) else { return }
        image = img
    }
}
