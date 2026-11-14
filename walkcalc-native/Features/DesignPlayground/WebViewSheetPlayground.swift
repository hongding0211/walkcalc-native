#if DEBUG
import SwiftUI

/// An offline blank page makes native safe-area and initial-page colors visible.
struct WebViewSheetPlayground: View {
    @State private var isPresented = false

    var body: some View {
        Button("Open web sheet") { isPresented = true }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $isPresented) {
                WebView(url: URL(string: "about:blank")!, onToken: nil)
                    .immersiveWebSheet()
            }
            .onAppear { isPresented = true }
    }
}

#Preview("Web sheet · Dark") {
    WebViewSheetPlayground().preferredColorScheme(.dark)
}

#Preview("Web sheet · Light") {
    WebViewSheetPlayground().preferredColorScheme(.light)
}
#endif
