import Foundation
#if canImport(Combine)
import Combine
#endif

/// Token returned by ``LetsBot/observeUnreadCount(_:)``. The observer is removed on ``cancel()`` or when this object
/// is deallocated — keep a strong reference for as long as you want updates.
public final class LetsBotObservation: NSObject {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    /// Stops the observation. Safe to call more than once.
    public func cancel() {
        let block = onCancel
        onCancel = nil
        block?()
    }

    deinit { cancel() }
}

/// Thread-safe unread counter fan-out: closures, `NotificationCenter` and Combine. Observers are called on main.
final class UnreadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    private var observers: [UUID: (Int) -> Void] = [:]
    #if canImport(Combine)
    private lazy var subject = CurrentValueSubject<Int, Never>(0)
    #endif

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    /// Sets a new value; notifies (on main) only when it changed.
    func update(_ newValue: Int, notify: @escaping (Int) -> Void = { _ in }) {
        let count = max(0, newValue)
        lock.lock()
        let changed = count != _value
        _value = count
        lock.unlock()
        guard changed else { return }
        onMain { [self] in
            #if canImport(Combine)
            subject.send(count)
            #endif
            for observer in snapshotObservers() { observer(count) }
            NotificationCenter.default.post(
                name: LetsBot.unreadCountDidChangeNotification,
                object: nil,
                userInfo: [LetsBot.unreadCountUserInfoKey: count]
            )
            notify(count)
        }
    }

    private func snapshotObservers() -> [(Int) -> Void] {
        lock.lock(); defer { lock.unlock() }
        return Array(observers.values)
    }

    func addObserver(_ observer: @escaping (Int) -> Void) -> LetsBotObservation {
        let id = UUID()
        lock.lock()
        observers[id] = observer
        let current = _value
        lock.unlock()
        onMain { observer(current) }
        return LetsBotObservation { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.observers[id] = nil
            self.lock.unlock()
        }
    }

    #if canImport(Combine)
    var publisher: AnyPublisher<Int, Never> {
        onMainSync { subject.removeDuplicates().eraseToAnyPublisher() }
    }
    #endif
}

func onMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
}

func onMainSync<T>(_ block: () -> T) -> T {
    if Thread.isMainThread { return block() }
    return DispatchQueue.main.sync(execute: block)
}
