import SwiftUI

struct ContentView: View {
    var connectivityManager = WatchConnectivityManager.shared

    var body: some View {
        NavigationStack {
            List {
                if connectivityManager.receivedFiles.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "heart.slash",
                        description: Text(
                            "Record heart rate data on your Apple Watch, then export it here."
                        )
                    )
                } else {
                    ForEach(connectivityManager.receivedFiles) { file in
                        VStack(alignment: .leading) {
                            Text(file.fileName)
                                .font(.headline)
                            Text(
                                "\(file.sampleCount) samples - \(file.startDate, style: .date)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            ShareLink(item: file.fileURL)
                        }
                    }
                }
            }
            .navigationTitle("beschluenige")
        }
    }
}

#Preview {
    ContentView()
}
