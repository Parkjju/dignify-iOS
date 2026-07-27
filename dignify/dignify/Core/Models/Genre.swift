//
//  Genre.swift
//  dignify
//
//  Created by 박경준 on 6/30/26.
//

struct Genre: Hashable, Identifiable {
    let id: Int
    /// 표시용 장르명 — 서버가 Accept-Language로 현지화해서 내려준다.
    let name: String
    /// 현지화되지 않은 원문 장르명. `name`은 ko 로케일에서 "힙합/랩"으로 내려와
    /// 퀴즈 점수표·장르 설명의 매칭 키로 쓸 수 없어 별도로 받는다.
    /// 백엔드 배포 전엔 nil — 그땐 en 로케일 한정으로 `name`이 같은 값이라 폴백이 먹힌다.
    var nameEn: String?

    // 장르 동일성은 id뿐.
    static func == (lhs: Genre, rhs: Genre) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
