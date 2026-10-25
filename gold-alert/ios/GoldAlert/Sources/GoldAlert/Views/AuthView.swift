import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var model: AppViewModel
    @FocusState private var tokenFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)

            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.09))

            Text("GOLD ALERT")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.09))

            Text("新设备输入一次 Token，本机以后不用再输入")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                SecureField("API Token", text: $model.tokenInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                    .focused($tokenFocused)

                TextField("Cloudflare 地址", text: $model.baseURLInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))

                Button {
                    Task { await model.unlock() }
                } label: {
                    Text(model.busy ? "验证中…" : "解锁")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.83, green: 0.63, blue: 0.09))
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
