import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppViewModel

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.04).ignoresSafeArea()

            if model.isUnlocked {
                MainView()
            } else {
                AuthView()
            }

            if let toast = model.toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(model.toastIsError
                                  ? Color(red: 0.75, green: 0.22, blue: 0.17)
                                  : Color.black)
                    )
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: model.toast)
            }
        }
        .onAppear { model.onAppear() }
    }
}
