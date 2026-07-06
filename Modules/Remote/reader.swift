//
//  reader.swift
//  Remote
//

import Kit

public final class DataReader: Reader<[LinuxServerState]> {
    private var task: Task<Void, Never>?
    private let taskLock = NSLock()
    private var lastSeen: [String: Date] = [:]

    public override func setup() {
        self.defaultInterval = 2
    }

    public override func read() {
        let servers = LinuxServersStore.load().filter(\.enabled)
        guard !servers.isEmpty else {
            self.callback([])
            return
        }

        self.taskLock.lock()
        self.task?.cancel()
        self.task = Task { [weak self] in
            let states = await withTaskGroup(of: LinuxServerState.self) { group -> [LinuxServerState] in
                for server in servers {
                    group.addTask {
                        switch await LinuxServerClient.fetchSnapshot(server) {
                        case .success(let snapshot):
                            return LinuxServerState(config: server, snapshot: snapshot, error: nil, lastSeen: snapshot.timestamp)
                        case .failure(let error):
                            return LinuxServerState(
                                config: server,
                                snapshot: nil,
                                error: error.localizedDescription,
                                lastSeen: nil
                            )
                        }
                    }
                }

                var values: [LinuxServerState] = []
                for await state in group {
                    values.append(state)
                }
                return values.sorted { $0.config.displayName.localizedCaseInsensitiveCompare($1.config.displayName) == .orderedAscending }
            }

            guard !Task.isCancelled else { return }
            let merged = self?.mergeLastSeen(states) ?? states
            self?.callback(merged)
        }
        self.taskLock.unlock()
    }

    public override func terminate() {
        self.taskLock.lock()
        self.task?.cancel()
        self.task = nil
        self.taskLock.unlock()
    }

    private func mergeLastSeen(_ states: [LinuxServerState]) -> [LinuxServerState] {
        states.map { state in
            if let seen = state.lastSeen {
                self.lastSeen[state.config.id] = seen
                return state
            }
            return LinuxServerState(
                config: state.config,
                snapshot: nil,
                error: state.error,
                lastSeen: self.lastSeen[state.config.id]
            )
        }
    }
}
