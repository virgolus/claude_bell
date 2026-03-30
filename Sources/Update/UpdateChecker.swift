import Foundation
import AppKit

@MainActor
final class UpdateChecker: ObservableObject {

    struct UpdateInfo {
        let version: String
        let build: Int
        let highlights: String
    }

    static let baseURL = "https://claude-bell.vercel.app"

    @Published var isDownloading = false
    @Published var downloadError: String?

    func checkForUpdate() async -> UpdateInfo? {
        guard let url = URL(string: "\(Self.baseURL)/changelog.json") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let releases = try JSONDecoder().decode([ChangelogRelease].self, from: data)
            guard let latest = releases.first, latest.build > AppVersion.build else { return nil }

            let dismissedBuild = AppDefaults.shared.integer(forKey: "dismissedUpdateBuild")
            if latest.build <= dismissedBuild { return nil }

            return UpdateInfo(version: latest.version, build: latest.build, highlights: latest.highlights)
        } catch {
            print("[UpdateChecker] Check failed: \(error)")
            return nil
        }
    }

    func downloadAndInstall() async {
        isDownloading = true
        downloadError = nil
        defer { isDownloading = false }

        do {
            let zipURL = URL(string: "\(Self.baseURL)/ClaudeBell.zip")!
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeBell-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Download zip
            let (localURL, _) = try await URLSession.shared.download(from: zipURL)
            let zipPath = tempDir.appendingPathComponent("ClaudeBell.zip")
            try FileManager.default.moveItem(at: localURL, to: zipPath)

            // Unzip
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", zipPath.path, "-d", tempDir.path]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else {
                throw UpdateError.unzipFailed
            }

            let newApp = tempDir.appendingPathComponent("ClaudeBell.app")
            guard FileManager.default.fileExists(atPath: newApp.path) else {
                throw UpdateError.appNotFound
            }

            // Replace current bundle
            let currentBundle = URL(fileURLWithPath: Bundle.main.bundlePath)
            try FileManager.default.removeItem(at: currentBundle)
            try FileManager.default.moveItem(at: newApp, to: currentBundle)

            // Relaunch: spawn a background shell that waits for us to exit, then opens the new app
            let pid = ProcessInfo.processInfo.processIdentifier
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = [
                "-c",
                "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"\(currentBundle.path)\""
            ]
            relaunch.standardOutput = FileHandle.nullDevice
            relaunch.standardError = FileHandle.nullDevice
            try relaunch.run()

            // Clean up temp
            try? FileManager.default.removeItem(at: tempDir)

            NSApp.terminate(nil)
        } catch {
            downloadError = error.localizedDescription
            print("[UpdateChecker] Install failed: \(error)")
        }
    }

    enum UpdateError: LocalizedError {
        case unzipFailed
        case appNotFound

        var errorDescription: String? {
            switch self {
            case .unzipFailed: return "Failed to unzip update"
            case .appNotFound: return "Update archive missing ClaudeBell.app"
            }
        }
    }
}
