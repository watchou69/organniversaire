import SwiftUI

/// Écran principal : la page web, un écran de lancement le temps du premier chargement, et un écran hors connexion.
struct RootView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = WebModel()

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            WebView(model: model)
                .ignoresSafeArea(.container, edges: .bottom)   // la barre d'onglets du site descend jusqu'en bas de l'écran
                .opacity(model.firstLoadDone ? 1 : 0)
            if !model.firstLoadDone && !model.offline {
                VStack(spacing: 18) {
                    Image("LaunchLogo").resizable().scaledToFit().frame(width: 96, height: 96)
                    ProgressView().tint(.white)
                }
            }
            if model.offline {
                OfflineView { model.reload() }
            }
            if model.loading && model.firstLoadDone {
                VStack { ProgressView(value: model.progress).tint(Color("AccentColor")).frame(height: 2); Spacer() }
            }
        }
        .onChange(of: state.pendingURL) { url in
            if let url { model.load(url); state.pendingURL = nil }
        }
        .onChange(of: state.pushToken) { _ in model.sendPushTokenIfPossible() }
    }
}

struct OfflineView: View {
    var retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("📡").font(.system(size: 56))
            Text("Pas de connexion").font(.title2.bold()).foregroundColor(.white)
            Text("Vérifiez votre connexion internet, puis réessayez.")
                .multilineTextAlignment(.center).foregroundColor(.white.opacity(0.8)).padding(.horizontal, 32)
            Button(action: retry) {
                Text("Réessayer").bold().padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Color("AccentColor")).foregroundColor(.white).clipShape(Capsule())
            }
        }
    }
}
