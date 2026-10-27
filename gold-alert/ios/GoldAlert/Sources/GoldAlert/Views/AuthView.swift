import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var tokenFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color(red: 0.9, green: 0.25, blue: 0.22))

            Text("提醒事项")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.appGold)

            Text("新设备输入一次 Token，本机以后不用再输入")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                SecureField("API Token", text: $model.tokenInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
                    .focused($tokenFocused)

                TextField("Cloudflare 地址", text: $model.baseURLInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))

                Button {
                    Task { await model.unlock() }
                } label: {
                    Text(model.busy ? "验证中…" : "解锁")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.appGold)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model.busy)

                if let err = model.authError, !err.isEmpty {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.9, green: 0.35, blue: 0.3))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer()
        }
        .onAppear { tokenFocused = true }
    }
}
