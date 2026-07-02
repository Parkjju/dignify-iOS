//
//  Feed.swift
//  dignify
//
//  Created by 박경준 on 7/1/26.
//

import Foundation

struct Feed {
    let trackId: Int
    let trackName: String
    let artistName: String
    let artworkUrl: String
    let previewUrl: String
    let trackViewUrl: String
    var isHyped: Bool
}

extension Feed {
    /// 백엔드는 iTunes 소스 아트워크 URL을 그대로 저장한다(100×100이 대부분이나
    /// 170×170 등도 섞여 있음). iTunes CDN은 URL의 `WxH` 사이즈 세그먼트를 바꾸면
    /// 임의 크기를 서빙하므로, 소스 크기와 무관하게 표시용으로 키운 URL을 만든다.
    /// 'x'가 숫자 사이에 오는 곳은 사이즈 세그먼트뿐이라(경로 해시는 hex) 정규식이 안전.
    func artworkURL(size: Int) -> URL? { artworkUrl.itunesArtworkURL(size: size) }

    init(_ item: API.FeedItem) {   // 서버 wire 타입 → 도메인 모델. 필드 1:1 복사.
        self.init(
            trackId: item.trackId,
            trackName: item.trackName,
            artistName: item.artistName,
            artworkUrl: item.artworkUrl,
            previewUrl: item.previewUrl,
            trackViewUrl: item.trackViewUrl,
            isHyped: item.isHyped
        )
    }
}

extension String {
    /// iTunes 아트워크 URL의 `WxH` 사이즈 세그먼트를 임의 크기로 바꾼다.
    /// 'x'가 숫자 사이에 오는 곳은 사이즈 세그먼트뿐이라(경로 해시는 hex) 정규식이 안전.
    /// Feed·TrackDetail 등 iTunes 소스 URL을 쓰는 곳에서 공유.
    func itunesArtworkURL(size: Int) -> URL? {
        URL(string: replacingOccurrences(
            of: "[0-9]+x[0-9]+", with: "\(size)x\(size)", options: .regularExpression))
    }
}
