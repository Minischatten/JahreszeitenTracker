import SwiftUI

struct FarmCardView: View {
    let farm: FarmData
    let state: SeasonState?
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 12 : 20) {
            Text(farm.displayName)
                .font(compact ? .headline : .title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 2 : 3)
                .frame(maxWidth: .infinity)

            if let state {
                let season = Season.allCases[state.seasonIndex]
                Image(season.assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: compact ? 150 : 256, maxHeight: compact ? 150 : 256)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 20))
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(season.name())
                        .font(compact ? .title3.weight(.medium) : .title.weight(.medium))
                    Text(CountdownDisplay.text(remaining: state.remaining))
                        .font(.system(size: compact ? 38 : 56, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityLabel(loc("Zeit bis zum Saisonwechsel", "Time until season change"))
                        .accessibilityValue(CountdownDisplay.text(remaining: state.remaining))
                    if !compact {
                        Text(loc("bis zum Jahreszeitenwechsel", "until the season changes"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                syncLabel
                if !compact {
                    Divider()
                    HStack(spacing: 12) {
                        Image(season.next.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc("Als Nächstes", "Up next"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(season.next.name()).font(.subheadline.weight(.medium))
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                Image(systemName: "leaf")
                    .font(.system(size: compact ? 56 : 80, weight: .light))
                    .foregroundStyle(.tertiary)
                    .frame(height: compact ? 150 : 256)
                    .accessibilityHidden(true)
                Text("—:—")
                    .font(.system(size: compact ? 38 : 56, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                syncLabel
            }
        }
        .padding(compact ? 20 : 28)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var syncLabel: some View {
        let status = FarmSyncState.forFarm(farm)
        return Label {
            Text(statusText(status))
        } icon: {
            Image(systemName: statusIcon(status))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    private func statusText(_ status: FarmSyncState) -> String {
        switch status {
        case .synchronized: return loc("Synchronisiert", "Synced")
        case .lastStand: return loc("Letzter Stand", "Last saved state")
        case .waiting: return loc("Warte auf Spielstand", "Waiting for save")
        }
    }
    private func statusIcon(_ status: FarmSyncState) -> String {
        switch status {
        case .synchronized: return "checkmark.circle"
        case .lastStand: return "clock"
        case .waiting: return "hourglass"
        }
    }
}
