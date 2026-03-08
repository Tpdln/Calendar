//
//  ContentView.swift
//  Calendar
//
//  Created by Cem Berke Tepedelen on 8.03.2026.
//

import SwiftUI
import UserNotifications

struct ContentView: View {
    enum Priority: String, Codable, CaseIterable, Equatable {
        case low, normal, high
    }

    struct Task: Identifiable, Codable, Equatable {
        let id: UUID
        var title: String
        var isCompleted: Bool = false
        var dueDate: Date?
        var priority: Priority = .normal

        enum CodingKeys: String, CodingKey { case id, title, isCompleted, dueDate, priority }

        init(id: UUID = UUID(), title: String, isCompleted: Bool = false, dueDate: Date? = nil, priority: Priority = .normal) {
            self.id = id
            self.title = title
            self.isCompleted = isCompleted
            self.dueDate = dueDate
            self.priority = priority
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
            self.title = try container.decode(String.self, forKey: .title)
            self.isCompleted = (try? container.decode(Bool.self, forKey: .isCompleted)) ?? false
            self.dueDate = try? container.decode(Date.self, forKey: .dueDate)
            self.priority = (try? container.decode(Priority.self, forKey: .priority)) ?? .normal
        }
    }
    
    @State private var tasks: [Task] = []
    @State private var newTaskTitle: String = ""
    @State private var newTaskDueDate: Date? = nil
    @State private var isDueDateEnabled: Bool = false
    @State private var showCompletedTasks: Bool = true
    @State private var selectedDate: Date = Date()
    @State private var newTaskDueTime: Date = Date()
    @State private var agendaNewTaskTime: Date = Date()
    @State private var isEditingTask: Bool = false
    @State private var editingTaskID: UUID? = nil
    @State private var editingTitle: String = ""
    @State private var editingDate: Date? = nil
    @State private var editingTime: Date = Date()
    @State private var editingIsDateEnabled: Bool = false
    
    @State private var newTaskPriority: Priority = .normal
    @State private var editingPriority: Priority = .normal
    
    private let tasksStorageKey = "tasks_storage_key"
    
    // MARK: - Notifications
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error { print("Notification permission error: \(error)") }
            if !granted { print("Notification permission not granted") }
        }
    }

    private func scheduleReminder(for task: Task) {
        guard let due = task.dueDate else { return }
        // Do not schedule for past dates
        if due <= Date() { return }
        let content = UNMutableNotificationContent()
        content.title = task.title
        let dateText = DateFormatter.localizedString(from: due, dateStyle: .short, timeStyle: .short)
        content.body = "Son teslim: \(dateText)"
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("Failed to schedule notification: \(error)") }
        }
    }

    private func cancelReminder(for task: Task) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }
    
    private func loadTasks() {
        if let data = UserDefaults.standard.data(forKey: tasksStorageKey) {
            do {
                let decoded = try JSONDecoder().decode([Task].self, from: data)
                tasks = decoded
            } catch {
                // If decoding fails, keep tasks empty
                print("Failed to decode tasks: \(error)")
            }
        }
    }
    
    private func saveTasks() {
        do {
            let data = try JSONEncoder().encode(tasks)
            UserDefaults.standard.set(data, forKey: tasksStorageKey)
        } catch {
            print("Failed to encode tasks: \(error)")
        }
    }
    
    private func combine(date: Date, time: Date) -> Date {
        var dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: time)
        dateComponents.hour = timeComponents.hour
        dateComponents.minute = timeComponents.minute
        dateComponents.second = timeComponents.second
        return Calendar.current.date(from: dateComponents) ?? date
    }
    
    private func priorityRank(_ p: Priority) -> Int {
        switch p {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
    
    var body: some View {
        TabView {
            // Görevler sekmesi (mevcut görünüm)
            VStack(spacing: 8) {
                Text("Günlük Görevlerim")
                    .font(.title2)
                
                Toggle("Tamamlananları Göster", isOn: $showCompletedTasks)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .padding(.horizontal)
                    .font(.subheadline)
                
                HStack(spacing: 12) {
                    Text("Toplam: \(tasks.count)")
                    Text("Tamamlanan: \(tasks.filter { $0.isCompleted }.count)")
                    Spacer()
                    Menu("Toplu İşlemler") {
                        Button("Tümünü tamamla") {
                            for i in tasks.indices { tasks[i].isCompleted = true }
                            for t in tasks { cancelReminder(for: t) }
                        }
                        Button("Tamamlananları geri al") {
                            for i in tasks.indices { tasks[i].isCompleted = false }
                            for t in tasks { scheduleReminder(for: t) }
                        }
                        Button(role: .destructive) {
                            for t in tasks where t.isCompleted { cancelReminder(for: t) }
                            tasks.removeAll { $0.isCompleted }
                        } label: {
                            Text("Tamamlananları Sil")
                        }
                    }
                }
                .font(.caption)
                .padding(.horizontal)
                
                let filteredTasks = showCompletedTasks ? tasks : tasks.filter { !$0.isCompleted }
                let sortedFilteredTasks = filteredTasks.sorted {
                    let r0 = priorityRank($0.priority)
                    let r1 = priorityRank($1.priority)
                    if r0 != r1 { return r0 < r1 }
                    switch ($0.dueDate, $1.dueDate) {
                    case let (date1?, date2?):
                        return date1 < date2
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        return false
                    }
                }
                
                List {
                    ForEach(sortedFilteredTasks) { task in
                        // Find index in tasks array for binding
                        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                            Button(action: {
                                tasks[index].isCompleted.toggle()
                                if tasks[index].isCompleted {
                                    cancelReminder(for: tasks[index])
                                } else {
                                    scheduleReminder(for: tasks[index])
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: tasks[index].isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(tasks[index].isCompleted ? .green : .primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(tasks[index].priority == .high ? Color.red : (tasks[index].priority == .normal ? Color.orange : Color.gray))
                                                .frame(width: 6, height: 6)
                                            Text(tasks[index].title)
                                                .strikethrough(tasks[index].isCompleted)
                                                .font(.body)
                                        }
                                        if let date = tasks[index].dueDate {
                                            HStack(spacing: 6) {
                                                Text(date, style: .date)
                                                Text(date, style: .time)
                                            }
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            if date < Date() && !tasks[index].isCompleted {
                                                Text("Gecikmiş")
                                                    .font(.caption2)
                                                    .foregroundColor(.red)
                                            }
                                        }
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Düzenle") {
                                    editingTaskID = task.id
                                    editingTitle = tasks[index].title
                                    if let due = tasks[index].dueDate {
                                        editingDate = due
                                        editingTime = due
                                        editingIsDateEnabled = true
                                    } else {
                                        editingDate = nil
                                        editingTime = Date()
                                        editingIsDateEnabled = false
                                    }
                                    editingPriority = tasks[index].priority
                                    isEditingTask = true
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        // Map indexSet from sortedFilteredTasks to tasks indices
                        let idsToDelete = indexSet.map { sortedFilteredTasks[$0].id }
                        // Cancel notifications for tasks being deleted
                        for id in idsToDelete {
                            if let t = tasks.first(where: { $0.id == id }) {
                                cancelReminder(for: t)
                            }
                        }
                        tasks.removeAll { idsToDelete.contains($0.id) }
                    }
                }
                .listStyle(.plain)
                
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Yeni görev başlığı", text: $newTaskTitle)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Ekle") {
                            let due = isDueDateEnabled ? combine(date: newTaskDueDate ?? Date(), time: newTaskDueTime) : nil
                            let task = Task(title: newTaskTitle, dueDate: due, priority: newTaskPriority)
                            tasks.append(task)
                            scheduleReminder(for: task)
                            newTaskTitle = ""
                            newTaskDueDate = nil
                            newTaskDueTime = Date()
                            isDueDateEnabled = false
                            newTaskPriority = .normal
                        }
                        .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                    
                    VStack(spacing: 4) {
                        Toggle("Son teslim tarihi ekle", isOn: $isDueDateEnabled)
                        
                        if isDueDateEnabled {
                            DatePicker("Son teslim tarihi", selection: Binding(
                                get: { newTaskDueDate ?? Date() },
                                set: { newTaskDueDate = $0 }
                            ), displayedComponents: .date)
                            .datePickerStyle(CompactDatePickerStyle())
                            .labelsHidden()
                            .padding(.horizontal)
                            
                            DatePicker("Saat", selection: $newTaskDueTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(CompactDatePickerStyle())
                                .labelsHidden()
                        }
                        Picker("Öncelik", selection: $newTaskPriority) {
                            Text("Düşük").tag(Priority.low)
                            Text("Normal").tag(Priority.normal)
                            Text("Yüksek").tag(Priority.high)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(.horizontal)
            }
            .tabItem { Label("Görevler", systemImage: "checklist") }
            
            // Ajanda sekmesi
            NavigationView {
                VStack(spacing: 12) {
                    DatePicker("Tarih", selection: $selectedDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .padding(.horizontal)
                    
                    let tasksForSelectedDate = tasks.filter { task in
                        if let due = task.dueDate {
                            let cal = Calendar.current
                            return cal.isDate(due, inSameDayAs: selectedDate)
                        } else {
                            return false
                        }
                    }
                    let sortedTasksForSelectedDate = tasksForSelectedDate.sorted { (a, b) in
                        let r0 = priorityRank(a.priority)
                        let r1 = priorityRank(b.priority)
                        if r0 != r1 { return r0 < r1 }
                        switch (a.dueDate, b.dueDate) {
                        case let (d1?, d2?): return d1 < d2
                        case (_?, nil): return true
                        case (nil, _?): return false
                        case (nil, nil): return false
                        }
                    }
                    let undatedTasks = tasks.filter { $0.dueDate == nil }
                    let sortedUndatedTasks = undatedTasks.sorted { priorityRank($0.priority) < priorityRank($1.priority) }
                    
                    List {
                        Section("Seçili Gün") {
                            if sortedTasksForSelectedDate.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "calendar.badge.exclamationmark")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                    Text("Bu tarihte görev yok")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical)
                            } else {
                                ForEach(sortedTasksForSelectedDate) { task in
                                    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                        HStack {
                                            Button {
                                                tasks[index].isCompleted.toggle()
                                                if tasks[index].isCompleted {
                                                    cancelReminder(for: tasks[index])
                                                } else {
                                                    scheduleReminder(for: tasks[index])
                                                }
                                            } label: {
                                                Image(systemName: tasks[index].isCompleted ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(tasks[index].isCompleted ? .green : .primary)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            VStack(alignment: .leading) {
                                                HStack(spacing: 6) {
                                                    Circle()
                                                        .fill(tasks[index].priority == .high ? Color.red : (tasks[index].priority == .normal ? Color.orange : Color.gray))
                                                        .frame(width: 6, height: 6)
                                                    Text(tasks[index].title)
                                                        .strikethrough(tasks[index].isCompleted)
                                                }
                                                if let date = tasks[index].dueDate {
                                                    HStack(spacing: 6) {
                                                        Text(date, style: .date)
                                                        Text(date, style: .time)
                                                    }
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button("Düzenle") {
                                                editingTaskID = task.id
                                                editingTitle = tasks[index].title
                                                if let due = tasks[index].dueDate {
                                                    editingDate = due
                                                    editingTime = due
                                                    editingIsDateEnabled = true
                                                } else {
                                                    editingDate = nil
                                                    editingTime = Date()
                                                    editingIsDateEnabled = false
                                                }
                                                editingPriority = tasks[index].priority
                                                isEditingTask = true
                                            }
                                            .tint(.blue)
                                        }
                                    }
                                }
                                .onDelete { indexSet in
                                    let ids = indexSet.map { sortedTasksForSelectedDate[$0].id }
                                    for id in ids {
                                        if let t = tasks.first(where: { $0.id == id }) {
                                            cancelReminder(for: t)
                                        }
                                    }
                                    tasks.removeAll { ids.contains($0.id) }
                                }
                            }
                        }
                        
                        Section("Tarihsiz Görevler") {
                            if sortedUndatedTasks.isEmpty {
                                Text("Tarihsiz görev yok")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(sortedUndatedTasks) { task in
                                    if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                        HStack {
                                            Button {
                                                tasks[index].isCompleted.toggle()
                                                if tasks[index].isCompleted {
                                                    cancelReminder(for: tasks[index])
                                                } else {
                                                    scheduleReminder(for: tasks[index])
                                                }
                                            } label: {
                                                Image(systemName: tasks[index].isCompleted ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(tasks[index].isCompleted ? .green : .primary)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            HStack(spacing: 6) {
                                                Circle()
                                                    .fill(tasks[index].priority == .high ? Color.red : (tasks[index].priority == .normal ? Color.orange : Color.gray))
                                                    .frame(width: 6, height: 6)
                                                Text(tasks[index].title)
                                                    .strikethrough(tasks[index].isCompleted)
                                            }
                                            Spacer()
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button("Düzenle") {
                                                editingTaskID = task.id
                                                editingTitle = tasks[index].title
                                                if let due = tasks[index].dueDate {
                                                    editingDate = due
                                                    editingTime = due
                                                    editingIsDateEnabled = true
                                                } else {
                                                    editingDate = nil
                                                    editingTime = Date()
                                                    editingIsDateEnabled = false
                                                }
                                                editingPriority = tasks[index].priority
                                                isEditingTask = true
                                            }
                                            .tint(.blue)
                                        }
                                    }
                                }
                                .onDelete { indexSet in
                                    let ids = indexSet.map { sortedUndatedTasks[$0].id }
                                    for id in ids {
                                        if let t = tasks.first(where: { $0.id == id }) {
                                            cancelReminder(for: t)
                                        }
                                    }
                                    tasks.removeAll { ids.contains($0.id) }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    
                    HStack(spacing: 8) {
                        TextField("Bu tarihe görev ekle", text: $newTaskTitle)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        DatePicker("Saat", selection: $agendaNewTaskTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Button("Ekle") {
                            let due = combine(date: selectedDate, time: agendaNewTaskTime)
                            let task = Task(title: newTaskTitle, dueDate: due, priority: newTaskPriority)
                            tasks.append(task)
                            scheduleReminder(for: task)
                            newTaskTitle = ""
                            agendaNewTaskTime = Date()
                            newTaskPriority = .normal
                        }
                        .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                    
                    Picker("Öncelik", selection: $newTaskPriority) {
                        Text("Düşük").tag(Priority.low)
                        Text("Normal").tag(Priority.normal)
                        Text("Yüksek").tag(Priority.high)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                .navigationTitle("Ajanda")
            }
            .tabItem { Label("Ajanda", systemImage: "calendar") }
        }
        .onAppear { loadTasks(); requestNotificationPermission() }
        .onChange(of: tasks) { saveTasks() }
        .sheet(isPresented: $isEditingTask) {
            NavigationView {
                VStack(spacing: 12) {
                    TextField("Görev başlığı", text: $editingTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                    Toggle("Son teslim tarihi kullan", isOn: $editingIsDateEnabled)
                        .padding(.horizontal)
                    if editingIsDateEnabled {
                        DatePicker("Tarih", selection: Binding(
                            get: { editingDate ?? Date() },
                            set: { editingDate = $0 }
                        ), displayedComponents: .date)
                        .datePickerStyle(CompactDatePickerStyle())
                        .labelsHidden()
                        .padding(.horizontal)
                        DatePicker("Saat", selection: $editingTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(CompactDatePickerStyle())
                            .labelsHidden()
                            .padding(.horizontal)
                    }
                    Picker("Öncelik", selection: $editingPriority) {
                        Text("Düşük").tag(Priority.low)
                        Text("Normal").tag(Priority.normal)
                        Text("Yüksek").tag(Priority.high)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    Spacer()
                }
                .navigationTitle("Görevi Düzenle")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Vazgeç") { isEditingTask = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kaydet") {
                            if let id = editingTaskID, let idx = tasks.firstIndex(where: { $0.id == id }) {
                                cancelReminder(for: tasks[idx])
                                tasks[idx].title = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                if editingIsDateEnabled {
                                    let dateBase = editingDate ?? Date()
                                    tasks[idx].dueDate = combine(date: dateBase, time: editingTime)
                                } else {
                                    tasks[idx].dueDate = nil
                                }
                                tasks[idx].priority = editingPriority
                                scheduleReminder(for: tasks[idx])
                            }
                            isEditingTask = false
                        }
                        .disabled(editingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

