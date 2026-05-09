import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    glucoseCommandCard
                    readinessRail
                    metricsSection
                    actionPanel
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(AppSurfaceBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $viewModel.isShowingSettings) {
                SettingsView(viewModel: viewModel)
            }
            .onAppear {
                viewModel.onAppear()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HealthSync")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text(viewModel.isUsingDemoData ? "Simulator preview" : "Personal health command center")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: viewModel.showSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.45), lineWidth: 1)
                    )
            }
            .accessibilityLabel("Settings")
        }
    }

    private var glucoseCommandCard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                GlucoseDial(
                    valueText: viewModel.glucoseSummary,
                    stateText: viewModel.glucoseBandTitle,
                    progress: viewModel.glucoseProgress,
                    tint: viewModel.glucoseTint
                )

                VStack(alignment: .leading, spacing: 14) {
                    StatusPill(
                        title: viewModel.glucoseBandTitle,
                        icon: "waveform.path.ecg",
                        color: viewModel.glucoseTint
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Metabolic Snapshot")
                            .font(.title3.weight(.bold))
                        Text(viewModel.glucoseBandDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(viewModel.glucoseSubtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlucoseRangeTrack(progress: viewModel.glucoseProgress, tint: viewModel.glucoseTint)

            if viewModel.isUsingDemoData {
                InfoBanner(
                    icon: "iphone.gen2",
                    title: "Preview data",
                    message: "The Simulator cannot read Apple Health, so this board uses sample metrics while preserving the real iPhone workflow."
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.09), radius: 24, y: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.55), lineWidth: 1)
        )
    }

    private var readinessRail: some View {
        HStack(spacing: 10) {
            ReadinessTile(
                icon: viewModel.isUsingDemoData ? "iphone.gen2" : "heart.fill",
                title: "Health",
                value: viewModel.healthKitValue,
                color: viewModel.isHealthKitAuthorized ? .green : .orange
            )
            ReadinessTile(
                icon: "server.rack",
                title: "Backend",
                value: viewModel.isConfigured ? "Ready" : "Setup",
                color: viewModel.isConfigured ? .green : .orange
            )
            ReadinessTile(
                icon: "clock.fill",
                title: "Last Sync",
                value: viewModel.lastSyncDate?.formatted(date: .omitted, time: .shortened) ?? "Never",
                color: .blue
            )
        }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Signal Grid", subtitle: "Current readings across movement, energy, and body metrics")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let heartRate = viewModel.latestHeartRate {
                    MetricTile(metric: heartRate, icon: "heart.fill", color: .red)
                }

                if let steps = viewModel.latestSteps {
                    MetricTile(metric: steps, icon: "figure.walk", color: .green)
                }

                if let energy = viewModel.latestActiveEnergy {
                    MetricTile(metric: energy, icon: "flame.fill", color: .orange)
                }

                if let weight = viewModel.latestWeight {
                    MetricTile(metric: weight, icon: "scalemass.fill", color: .purple)
                }
            }

            if viewModel.hasNoMetrics {
                EmptyStateCard(
                    icon: "waveform.path.ecg",
                    title: "No readings yet",
                    message: "Authorize HealthKit on your iPhone to fill this board with glucose, heart rate, steps, energy, and weight."
                )
            }
        }
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Pipeline")
                        .font(.headline)
                    Text(syncPanelSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: viewModel.canSync ? "bolt.horizontal.circle.fill" : "lock.circle.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.canSync ? .green : .orange)
            }

            if !viewModel.isHealthKitAuthorized && !viewModel.isUsingDemoData {
                Button(action: viewModel.authorizeHealthKit) {
                    Label("Authorize HealthKit", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle(color: .pink))
            }

            Button(action: viewModel.syncNow) {
                Label(viewModel.syncButtonTitle, systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle(color: viewModel.canSync ? .blue : .gray))
            .disabled(!viewModel.canSync)

            if !viewModel.syncStatus.isEmpty || !viewModel.healthKitStatusMessage.isEmpty {
                InfoBanner(
                    icon: statusIcon,
                    title: statusTitle,
                    message: viewModel.syncStatus.isEmpty ? viewModel.healthKitStatusMessage : viewModel.syncStatus
                )
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.5), lineWidth: 1)
        )
    }

    private var syncPanelSubtitle: String {
        if !viewModel.isConfigured {
            return "Add backend credentials to unlock sync."
        }
        if viewModel.isUsingDemoData {
            return "Use an iPhone for real HealthKit syncing."
        }
        return viewModel.canSync ? "Ready to send recent samples." : "Waiting for HealthKit permission."
    }

    private var statusIcon: String {
        viewModel.syncStatus.contains("failed") || viewModel.syncStatus.contains("Invalid") ? "exclamationmark.triangle.fill" : "info.circle.fill"
    }

    private var statusTitle: String {
        viewModel.syncStatus.isEmpty ? "HealthKit" : "Sync Status"
    }
}

struct AppSurfaceBackground: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [
                    Color.green.opacity(0.16),
                    Color.blue.opacity(0.08),
                    Color.orange.opacity(0.10),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

struct GlucoseDial: View {
    let valueText: String
    let stateText: String
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(.black.opacity(0.06), lineWidth: 15)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.35), tint, .blue.opacity(0.85), tint],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text(valueText)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(stateText.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(tint)
                    .tracking(1.4)
            }
            .padding(14)
        }
        .frame(width: 142, height: 142)
        .padding(6)
        .background(
            Circle()
                .fill(.background)
                .shadow(color: tint.opacity(0.22), radius: 18, y: 8)
        )
    }
}

struct GlucoseRangeTrack: View {
    let progress: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let markerX = max(8, min(proxy.size.width - 8, proxy.size.width * progress))

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.orange, .green, .yellow, .red],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 12)

                    Circle()
                        .fill(.background)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(tint, lineWidth: 5))
                        .offset(x: markerX - 11)
                }
            }
            .frame(height: 24)

            HStack {
                Text("Low")
                Spacer()
                Text("Target")
                Spacer()
                Text("High")
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
        }
    }
}

struct StatusPill: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.black))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(color.opacity(0.13), in: Capsule())
    }
}

struct ReadinessTile: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .background(.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.heavy))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MetricTile: View {
    let metric: HealthMetric
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer()

                Text(metric.date, style: .time)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 5) {
                Text(metric.type)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatValue(metric.value))
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.62)
                        .lineLimit(1)
                    Text(metric.unit)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.background)
        )
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(height: 5)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .shadow(color: color.opacity(0.10), radius: 14, y: 8)
    }

    private func formatValue(_ value: Double) -> String {
        switch metric.type {
        case "Weight":
            return String(format: "%.1f", value)
        default:
            return String(format: "%.0f", value)
        }
    }
}

struct InfoBanner: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.blue)
                .frame(width: 24, height: 24)
                .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.bold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .background(color.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("API Configuration") {
                    TextField("API URL", text: $viewModel.apiUrl)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    SecureField("API Secret", text: $viewModel.apiSecret)
                        .textContentType(.password)

                    TextField("User ID", text: $viewModel.userId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                }

                Section("Status") {
                    LabeledContent("API URL", value: viewModel.apiUrl.trimmed.isEmpty ? "Missing" : "Ready")
                    LabeledContent("API Secret", value: viewModel.apiSecret.trimmed.isEmpty ? "Missing" : "Ready")
                    LabeledContent("User ID", value: viewModel.userId.trimmed.isEmpty ? "Missing" : "Ready")
                }

                Section("Example") {
                    Text("https://your-service.run.app")
                    Text("Use an email address or another stable unique identifier for User ID.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        viewModel.closeSettings()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.saveSettings()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    ContentView(viewModel: DashboardViewModel())
}
