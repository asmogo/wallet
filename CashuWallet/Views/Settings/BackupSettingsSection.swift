import SwiftUI

struct BackupSettingsSection: View {
    @EnvironmentObject var walletManager: WalletManager

    @Binding var showBackup: Bool
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var mintBackupService = NostrMintBackupService.shared
    @State private var mintBackupError: String?

    var body: some View {
        Button {
            showBackup = true
        } label: {
            backupRestoreRow(
                title: "Backup seed phrase",
                subtitle: "View and copy your 12 recovery words.",
                systemImage: "key.fill"
            )
        }

        Toggle(isOn: $settings.nostrMintBackupEnabled) {
            backupRestoreRow(
                title: "Automatic Nostr mint backup",
                subtitle: settings.nostrMintBackupEnabled ? "Backups are on." : "Backups are off.",
                systemImage: "antenna.radiowaves.left.and.right"
            )
        }

        Button(action: backupMintsNow) {
            backupRestoreRow(
                title: mintBackupService.isBackingUp ? "Backing up mints..." : "Back up mints now",
                subtitle: mintBackupSubtitle,
                systemImage: "tray.and.arrow.up.fill"
            )
        }
        .disabled(walletManager.mints.isEmpty || mintBackupService.isBackingUp)
        .opacity(walletManager.mints.isEmpty ? 0.5 : 1)

        NavigationLink {
            RestoreWalletView()
                .environmentObject(walletManager)
        } label: {
            backupRestoreRow(
                title: "Restore",
                subtitle: "Restore a wallet and recover ecash from mints.",
                systemImage: "arrow.counterclockwise.circle.fill"
            )
        }
    }

    private func backupRestoreRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var mintBackupSubtitle: String {
        if let mintBackupError {
            return mintBackupError
        }
        if walletManager.mints.isEmpty {
            return "No mints to back up."
        }
        if let lastBackupDate = mintBackupService.lastBackupDate {
            return "Last backup \(relativeDate(lastBackupDate))."
        }
        return "Encrypted mint list backup."
    }

    private func backupMintsNow() {
        mintBackupError = nil
        let mintURLs = walletManager.mints.map(\.url)

        Task { @MainActor in
            do {
                try await mintBackupService.backupMintURLs(mintURLs)
                HapticFeedback.notification(.success)
            } catch {
                mintBackupError = error.localizedDescription
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
