import SwiftUI
import PostHog

/// 취향 테스트 문항 화면. 한 화면에 한 문항, 탭하면 바로 다음으로 넘어간다.
/// 확인 버튼을 두지 않는 건 문항이 11개라 탭 수가 두 배가 되기 때문.
struct TasteQuizView: View {
    /// 온보딩과 재검사가 같은 화면을 쓴다. 태그가 없으면 재검사 중도이탈이
    /// 온보딩 퍼널에 섞여 이탈률이 실제보다 나빠 보인다.
    var source: String = "onboarding"
    var onFinish: ([Int]) -> Void
    var onSkip: () -> Void

    @State private var index = 0
    @State private var answers: [Int] = []

    private var question: TasteQuiz.Question { TasteQuiz.questions[index] }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(question.prompt)
                        .font(DSTypography.title1)
                        .tracking(-0.48)
                        .foregroundStyle(DSColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        ForEach(Array(question.options.enumerated()), id: \.offset) { i, option in
                            optionRow(option.label) { answer(i) }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(DSColor.background)
        // 문항이 바뀌면 스크롤 위치·전환 애니메이션이 새로 걸리게 한다.
        .animation(.easeOut(duration: 0.2), value: index)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                if index > 0 {
                    Button {
                        index -= 1
                        answers = Array(answers.prefix(index))
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }
                Spacer()
                // 몇 번째 문항에서 나갔는지가 문항 수를 줄일지 판단하는 근거가 된다.
                Button("Skip") {
                    PostHogSDK.shared.capture(
                        "quiz_abandoned",
                        properties: ["at_question": index, "source": source]
                    )
                    onSkip()
                }
                    .font(DSTypography.bodyMedium)
                    .foregroundStyle(DSColor.textTertiary)
            }
            .frame(height: 44)

            ProgressView(value: Double(index + 1), total: Double(TasteQuiz.questions.count))
                .tint(DSColor.brand)
        }
        .padding(.horizontal, 24)
    }

    private func optionRow(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DSTypography.bodyMedium)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSRadius.medium))
        }
        .buttonStyle(PressScaleStyle())
    }

    private func answer(_ choice: Int) {
        answers.append(choice)
        if index + 1 < TasteQuiz.questions.count {
            index += 1
        } else {
            onFinish(answers)
        }
    }
}

/// 눌림 피드백만 주는 스타일. DSPrimaryButtonStyle은 색·높이가 고정이라 여기엔 안 맞는다.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    TasteQuizView(onFinish: { _ in }, onSkip: {})
}
