import SwiftUI

/// Settings view section and sheet editors for AMORA Automations V1.
struct AmoraAutomationSettingsView: View {
    @Bindable var service = AmoraAutomationService.shared
    @State private var showingCreateSheet = false
    @State private var editingAutomation: AmoraAutomation? = nil
    @State private var showingClearAllConfirmation = false
    @State private var statusFeedback: String? = nil

    private var palette: ThemePalette { AppState.shared.settings.palette }

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automations")
                            .font(.headline)
                        Text("Persistent, local automations triggered by schedule, battery, or focus timer.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
            }

            if let feedback = statusFeedback {
                Section {
                    Text(feedback)
                        .font(.caption)
                        .foregroundStyle(palette.accent)
                }
            }

            Section("Active Automations (\(service.automations.count))") {
                if service.automations.isEmpty {
                    VStack(spacing: 8) {
                        Text("No automations configured yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Create an automation or tell AMORA: “Remind me every day at 9 PM.”")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                } else {
                    ForEach(service.automations) { auto in
                        automationRow(auto)
                    }

                    Button("Clear All Automations", role: .destructive) {
                        showingClearAllConfirmation = true
                    }
                    .font(.caption)
                    .padding(.top, 4)
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            AmoraAutomationEditSheet(automation: nil) { newAuto in
                Task {
                    do {
                        try await service.create(
                            name: newAuto.name,
                            trigger: newAuto.trigger,
                            condition: newAuto.condition,
                            action: newAuto.action,
                            schedule: newAuto.schedule,
                            enabled: newAuto.enabled
                        )
                        statusFeedback = "Created \(newAuto.name)."
                    } catch {
                        statusFeedback = "Failed to create: \(error.localizedDescription)"
                    }
                }
            }
        }
        .sheet(item: $editingAutomation) { target in
            AmoraAutomationEditSheet(automation: target) { updated in
                Task {
                    do {
                        try await service.update(updated)
                        statusFeedback = "Updated \(updated.name)."
                    } catch {
                        statusFeedback = "Failed to update: \(error.localizedDescription)"
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete All Automations?",
            isPresented: $showingClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task {
                    await service.clearAll(confirmed: true)
                    statusFeedback = "All automations deleted."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all stored automations. This action cannot be undone.")
        }
    }

    private func automationRow(_ auto: AmoraAutomation) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { auto.enabled },
                set: { _ in
                    Task {
                        try? await service.toggleEnabled(id: auto.id)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(auto.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if !auto.enabled {
                        Text("Off")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.2)))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: auto.trigger.systemImage)
                        .font(.caption2)
                    Text(auto.trigger.displayName)
                        .font(.caption)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: auto.action.systemImage)
                        .font(.caption2)
                    Text(auto.action.displayName)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                if auto.enabled, let next = auto.nextRunAt {
                    Text("Next run: \(formatRunDate(next))")
                        .font(.caption2)
                        .foregroundStyle(palette.accent)
                } else if let last = auto.lastRunAt {
                    Text("Last run: \(formatRunDate(last))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Run test button
            Button {
                Task {
                    let result = await service.runManually(id: auto.id)
                    statusFeedback = result?.message ?? "Executed \(auto.name)."
                }
            } label: {
                Image(systemName: "play.fill")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Run manually")

            // Edit button
            Button {
                editingAutomation = auto
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Edit")

            // Delete button
            Button(role: .destructive) {
                Task {
                    _ = await service.delete(id: auto.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.vertical, 4)
    }

    private func formatRunDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// Modal sheet for creating and editing an automation.
struct AmoraAutomationEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let automation: AmoraAutomation?
    let onSave: (AmoraAutomation) -> Void

    @State private var name: String = ""
    @State private var triggerType: TriggerKind = .daily
    @State private var dailyHour: Int = 9
    @State private var dailyMinute: Int = 0
    @State private var intervalMinutes: Int = 30
    @State private var oneTimeDate: Date = Date().addingTimeInterval(3600)
    @State private var batteryThreshold: Int = 20
    @State private var batteryComparison: BatteryComparison = .dropsBelow

    @State private var actionType: ActionKind = .showNotification
    @State private var notificationMessage: String = "Take a quick stretch!"
    @State private var timerMinutes: Int = 25
    @State private var appName: String = "Spotify"
    @State private var workspaceSection: String = "overview"

    enum TriggerKind: String, CaseIterable, Identifiable {
        case daily = "Daily"
        case weekdays = "Weekdays"
        case interval = "Interval"
        case oneTime = "One-Time"
        case battery = "Battery"
        case timerCompletion = "Timer Done"
        var id: String { rawValue }
    }

    enum ActionKind: String, CaseIterable, Identifiable {
        case showNotification = "Notification"
        case startTimer = "Start Timer"
        case openApp = "Open App"
        case openWorkspace = "Workspace"
        case mediaPlay = "Play Music"
        case mediaPause = "Pause Music"
        case mediaNext = "Next Track"
        case mediaPrevious = "Previous Track"
        var id: String { rawValue }
    }

    init(automation: AmoraAutomation?, onSave: @escaping (AmoraAutomation) -> Void) {
        self.automation = automation
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(automation == nil ? "New Automation" : "Edit Automation")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            Form {
                Section("Details") {
                    TextField("Automation Name", text: $name)
                }

                Section("Trigger") {
                    Picker("Trigger Type", selection: $triggerType) {
                        ForEach(TriggerKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }

                    switch triggerType {
                    case .daily, .weekdays:
                        HStack {
                            Picker("Hour", selection: $dailyHour) {
                                ForEach(0..<24) { h in
                                    let period = h >= 12 ? "PM" : "AM"
                                    let hour12 = h % 12 == 0 ? 12 : h % 12
                                    Text("\(hour12) \(period)").tag(h)
                                }
                            }
                            Picker("Minute", selection: $dailyMinute) {
                                ForEach([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55], id: \.self) { m in
                                    Text(String(format: "%02d", m)).tag(m)
                                }
                            }
                        }
                    case .interval:
                        Stepper("Every \(intervalMinutes) minutes", value: $intervalMinutes, in: 1...720, step: 5)
                    case .oneTime:
                        DatePicker("Run At", selection: $oneTimeDate)
                    case .battery:
                        Stepper("Battery level: \(batteryThreshold)%", value: $batteryThreshold, in: 5...95, step: 5)
                        Picker("Condition", selection: $batteryComparison) {
                            Text("Drops Below or Reaches").tag(BatteryComparison.dropsBelow)
                            Text("Rises Above or Reaches").tag(BatteryComparison.risesAbove)
                        }
                    case .timerCompletion:
                        Text("Triggers immediately when an active focus timer finishes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Action") {
                    Picker("Action Type", selection: $actionType) {
                        ForEach(ActionKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }

                    switch actionType {
                    case .showNotification:
                        TextField("Notification Message", text: $notificationMessage)
                    case .startTimer:
                        Stepper("\(timerMinutes) minutes", value: $timerMinutes, in: 1...180, step: 5)
                    case .openApp:
                        TextField("Application Name", text: $appName)
                    case .openWorkspace:
                        Picker("Section", selection: $workspaceSection) {
                            Text("Overview").tag("overview")
                            Text("Music").tag("music")
                            Text("Timer").tag("timer")
                            Text("Notes").tag("notes")
                            Text("Files").tag("files")
                            Text("Clipboard").tag("clipboard")
                        }
                    case .mediaPlay, .mediaPause, .mediaNext, .mediaPrevious:
                        EmptyView()
                    }
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Save") {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .frame(width: 440, height: 460)
        .onAppear {
            if let target = automation {
                name = target.name
                switch target.trigger {
                case .daily(let h, let m):
                    triggerType = .daily
                    dailyHour = h
                    dailyMinute = m
                case .weekdays(let h, let m):
                    triggerType = .weekdays
                    dailyHour = h
                    dailyMinute = m
                case .interval(let s):
                    triggerType = .interval
                    intervalMinutes = max(1, Int(s / 60))
                case .oneTime(let d):
                    triggerType = .oneTime
                    oneTimeDate = d
                case .batteryThreshold(let lvl, let comp):
                    triggerType = .battery
                    batteryThreshold = lvl
                    batteryComparison = comp
                case .timerCompletion:
                    triggerType = .timerCompletion
                }

                switch target.action {
                case .showNotification(let msg):
                    actionType = .showNotification
                    notificationMessage = msg
                case .startTimer(let duration):
                    actionType = .startTimer
                    timerMinutes = max(1, Int(duration / 60))
                case .openApp(let app):
                    actionType = .openApp
                    appName = app
                case .openWorkspace(let sec):
                    actionType = .openWorkspace
                    workspaceSection = sec ?? "overview"
                case .mediaPlay:
                    actionType = .mediaPlay
                case .mediaPause:
                    actionType = .mediaPause
                case .mediaNext:
                    actionType = .mediaNext
                case .mediaPrevious:
                    actionType = .mediaPrevious
                }
            }
        }
    }

    private func saveAndDismiss() {
        let trigger: AmoraAutomationTrigger
        switch triggerType {
        case .daily:
            trigger = .daily(hour: dailyHour, minute: dailyMinute)
        case .weekdays:
            trigger = .weekdays(hour: dailyHour, minute: dailyMinute)
        case .interval:
            trigger = .interval(seconds: TimeInterval(intervalMinutes * 60))
        case .oneTime:
            trigger = .oneTime(date: oneTimeDate)
        case .battery:
            trigger = .batteryThreshold(level: batteryThreshold, comparison: batteryComparison)
        case .timerCompletion:
            trigger = .timerCompletion
        }

        let action: AmoraAutomationAction
        switch actionType {
        case .showNotification:
            action = .showNotification(message: notificationMessage.trimmingCharacters(in: .whitespacesAndNewlines))
        case .startTimer:
            action = .startTimer(duration: TimeInterval(timerMinutes * 60))
        case .openApp:
            action = .openApp(name: appName.trimmingCharacters(in: .whitespacesAndNewlines))
        case .openWorkspace:
            action = .openWorkspace(section: workspaceSection)
        case .mediaPlay:
            action = .mediaPlay
        case .mediaPause:
            action = .mediaPause
        case .mediaNext:
            action = .mediaNext
        case .mediaPrevious:
            action = .mediaPrevious
        }

        let newAuto = AmoraAutomation(
            id: automation?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            trigger: trigger,
            condition: automation?.condition,
            action: action,
            schedule: trigger.defaultSchedule,
            enabled: automation?.enabled ?? true,
            createdAt: automation?.createdAt ?? Date(),
            updatedAt: Date(),
            lastRunAt: automation?.lastRunAt,
            nextRunAt: nil
        )

        onSave(newAuto)
        dismiss()
    }
}
