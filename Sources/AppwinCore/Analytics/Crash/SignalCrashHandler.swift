import Darwin
import Foundation
import os

/// Fatal signals (`SIGSEGV`, Swift traps as `SIGTRAP`, `abort()` as
/// `SIGABRT`...), recorded by an async-signal-safe handler.
///
/// The handler may not allocate, take a lock, or call into the Swift or
/// Objective-C runtime: the crashing thread may hold the malloc lock, or the
/// heap may be what got corrupted. So everything it touches is allocated at
/// install time and never freed, the output file descriptor is opened in
/// advance, and the handler only copies raw words into it with `write(2)`:
/// the signal, the time, the return addresses, and a context snapshot the
/// app refreshed beforehand. The next launch turns that into a report
/// (`SignalCrashFile`), resolving addresses against the image list the
/// crashed process saved, since ASLR moves every image on relaunch.
///
/// Limits, accepted: the alternate stack (needed to survive a stack
/// overflow) only covers the thread that installed it, the main thread; a
/// debugger catches these signals before the app does; and a frame-pointer
/// walk loses frames of code built without frame pointers.
enum SignalCrashHandler {
  static let signals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE]
  static let maxFrames = 128
  static let contextCapacity = 8192

  @MainActor private static var installed = false

  /// Opens `pendingFile` (truncated: convert any previous crash first) and
  /// installs the handlers, chained to the ones already there. Handlers are
  /// installed once per process; a later call only retargets the file.
  @MainActor
  @discardableResult
  static func install(pendingFile: URL) -> Bool {
    let memory = signalMemory
    let fd = open(pendingFile.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
    guard fd >= 0 else { return false }
    let previousFd = memory.fd.pointee
    memory.fd.pointee = fd
    if previousFd >= 0 { close(previousFd) }

    guard !installed else { return true }
    installed = true
    installAlternateStack()
    for (slot, number) in signals.enumerated() {
      var action = sigaction()
      action.__sigaction_u.__sa_sigaction = appwinSignalHandler
      action.sa_flags = SA_SIGINFO | SA_ONSTACK
      sigemptyset(&action.sa_mask)
      sigaction(number, &action, memory.previous + slot)
    }
    return true
  }

  /// Consent `denied` mutes the handler without uninstalling it: the chain
  /// stays intact for the handlers installed after it.
  static func setEnabled(_ enabled: Bool) {
    signalMemory.flags[SignalFlag.enabled] = enabled ? 1 : 0
  }

  /// An uncaught NSException ends in `abort()`: its report is already
  /// written, the `SIGABRT` that follows must not make a second one.
  static func markExceptionRecorded() {
    signalMemory.flags[SignalFlag.exceptionRecorded] = 1
  }

  /// Copies the context the handler will write verbatim. Double-buffered: a
  /// crash during an update reads the previous complete snapshot.
  static func updateContext(_ data: Data) {
    let memory = signalMemory
    os_unfair_lock_lock(memory.contextLock)
    defer { os_unfair_lock_unlock(memory.contextLock) }
    let target = 1 - Int(memory.flags[SignalFlag.published])
    let length = min(data.count, contextCapacity)
    data.copyBytes(to: memory.contexts + target * contextCapacity, count: length)
    memory.contextLengths[target] = length
    memory.flags[SignalFlag.published] = Int32(target)
  }

  private static func installAlternateStack() {
    var current = stack_t()
    // Another crash reporter may have installed one already; keep it.
    guard sigaltstack(nil, &current) == 0, current.ss_flags & SS_DISABLE != 0 else { return }
    let size = Int(SIGSTKSZ)
    guard let stackMemory = malloc(size) else { return }
    var stack = stack_t(ss_sp: stackMemory, ss_size: size, ss_flags: 0)
    sigaltstack(&stack, nil)
  }

  fileprivate static func slot(of number: Int32) -> Int {
    switch number {
    case SIGABRT: return 0
    case SIGSEGV: return 1
    case SIGBUS: return 2
    case SIGILL: return 3
    case SIGTRAP: return 4
    case SIGFPE: return 5
    default: return -1
    }
  }

  /// Hands the signal to the handler installed before ours (Crashlytics,
  /// Sentry), then dies with the original signal so the OS still writes its
  /// own crash log.
  fileprivate static func chain(
    _ number: Int32, _ info: UnsafeMutablePointer<__siginfo>?, _ uap: UnsafeMutableRawPointer?,
    _ memory: SignalMemory
  ) {
    let slot = slot(of: number)
    if slot >= 0 {
      let previous = memory.previous + slot
      sigaction(number, previous, nil)
      let raw = withUnsafeBytes(of: previous.pointee.__sigaction_u) { $0.load(as: UInt.self) }
      // 0 and 1 are SIG_DFL and SIG_IGN.
      if raw > 1 {
        if previous.pointee.sa_flags & SA_SIGINFO != 0 {
          previous.pointee.__sigaction_u.__sa_sigaction(number, info, uap)
        } else {
          previous.pointee.__sigaction_u.__sa_handler(number)
        }
      }
    }
    // Blocked while this handler runs: delivered, with the default action,
    // as soon as it returns.
    Darwin.signal(number, SIG_DFL)
    raise(number)
  }
}

enum SignalFlag {
  static let enabled = 0
  static let exceptionRecorded = 1
  static let published = 2
}

/// Raw memory owned by the handler. A struct of pointers rather than a
/// class: reading it from the handler involves no reference counting.
struct SignalMemory {
  let fd: UnsafeMutablePointer<Int32>
  let flags: UnsafeMutablePointer<Int32>
  let handlerLock: UnsafeMutablePointer<os_unfair_lock>
  let contextLock: UnsafeMutablePointer<os_unfair_lock>
  let contextLengths: UnsafeMutablePointer<Int>
  let contexts: UnsafeMutablePointer<UInt8>
  let previous: UnsafeMutablePointer<sigaction>
  let frames: UnsafeMutablePointer<UInt64>
  let scratch: UnsafeMutablePointer<UInt8>

  static func allocate() -> SignalMemory {
    let memory = SignalMemory(
      fd: .allocate(capacity: 1),
      flags: .allocate(capacity: 3),
      handlerLock: .allocate(capacity: 1),
      contextLock: .allocate(capacity: 1),
      contextLengths: .allocate(capacity: 2),
      contexts: .allocate(capacity: 2 * SignalCrashHandler.contextCapacity),
      previous: .allocate(capacity: SignalCrashHandler.signals.count),
      frames: .allocate(capacity: SignalCrashHandler.maxFrames),
      scratch: .allocate(capacity: SignalCrashWriter.scratchCapacity))
    memory.fd.initialize(to: -1)
    memory.flags.initialize(repeating: 0, count: 3)
    memory.flags[SignalFlag.enabled] = 1
    memory.handlerLock.initialize(to: os_unfair_lock())
    memory.contextLock.initialize(to: os_unfair_lock())
    memory.contextLengths.initialize(repeating: 0, count: 2)
    memory.previous.initialize(repeating: sigaction(), count: SignalCrashHandler.signals.count)
    return memory
  }
}

/// Initialized on first use, at install: from then on the handler's access
/// is a plain load.
nonisolated(unsafe) private let signalMemory = SignalMemory.allocate()

private func appwinSignalHandler(
  _ number: Int32, _ info: UnsafeMutablePointer<__siginfo>?, _ uap: UnsafeMutableRawPointer?
) {
  let memory = signalMemory
  // One record per process death: a second thread crashing at the same time
  // goes straight to the chain.
  if os_unfair_lock_trylock(memory.handlerLock),
     memory.flags[SignalFlag.enabled] != 0,
     memory.flags[SignalFlag.exceptionRecorded] == 0,
     memory.fd.pointee >= 0 {
    let count = SignalUnwinder.capture(uap, into: memory.frames, capacity: SignalCrashHandler.maxFrames)
    let published = Int(memory.flags[SignalFlag.published])
    var now = timespec()
    clock_gettime(CLOCK_REALTIME, &now)
    SignalCrashWriter.write(
      fd: memory.fd.pointee,
      signal: number,
      timeMs: Int64(now.tv_sec) * 1000 + Int64(now.tv_nsec / 1_000_000),
      frames: memory.frames,
      count: count,
      context: memory.contexts + published * SignalCrashHandler.contextCapacity,
      contextLength: memory.contextLengths[published],
      scratch: memory.scratch)
  }
  SignalCrashHandler.chain(number, info, uap, memory)
}

/// Return addresses of the crashed thread, from the register state the
/// kernel saved. `backtrace()` would walk the handler's own stack, which on
/// the alternate stack does not lead back to the crashed frames.
enum SignalUnwinder {
  #if arch(arm64)
  /// Strips pointer-authentication bits from signed return addresses.
  private static let addressMask: UInt64 = 0x0000_000F_FFFF_FFFF
  #else
  private static let addressMask: UInt64 = .max
  #endif

  static func capture(
    _ uap: UnsafeMutableRawPointer?, into buffer: UnsafeMutablePointer<UInt64>, capacity: Int
  ) -> Int {
    guard let uap, let mcontext = uap.assumingMemoryBound(to: ucontext_t.self).pointee.uc_mcontext
    else { return 0 }
    #if arch(arm64)
    let registers = mcontext.pointee.__ss
    let (pc, lr, fp) = (registers.__pc, registers.__lr, registers.__fp)
    #elseif arch(x86_64)
    let registers = mcontext.pointee.__ss
    let (pc, lr, fp) = (registers.__rip, UInt64(0), registers.__rbp)
    #else
    return 0
    #endif
    let thread = pthread_self()
    let high = UInt64(UInt(bitPattern: pthread_get_stackaddr_np(thread)))
    let low = high &- UInt64(pthread_get_stacksize_np(thread))
    return walk(
      pc: pc, lr: lr, fp: fp, stackLow: low, stackHigh: high, into: buffer, capacity: capacity)
  }

  /// Frame-pointer walk: each frame record is `[previous fp, return
  /// address]`. Every fp is checked against the thread's stack before it is
  /// read, so a corrupted chain ends the walk instead of faulting again.
  static func walk(
    pc: UInt64, lr: UInt64, fp: UInt64, stackLow: UInt64, stackHigh: UInt64,
    into buffer: UnsafeMutablePointer<UInt64>, capacity: Int
  ) -> Int {
    var count = 0
    let crashed = pc & addressMask
    if crashed != 0, count < capacity {
      buffer[count] = crashed
      count += 1
    }
    // The link register is the caller of a leaf function, which never
    // pushed a frame record. When the function did push one, the first
    // record repeats it: skipped below.
    let link = lr & addressMask
    if link != 0, count < capacity {
      buffer[count] = link
      count += 1
    }
    var frame = fp
    var first = true
    while count < capacity, frame >= stackLow, frame &+ 16 <= stackHigh, frame % 8 == 0 {
      guard let record = UnsafePointer<UInt64>(bitPattern: UInt(frame)) else { break }
      let next = record[0]
      let returnAddress = record[1] & addressMask
      if returnAddress == 0 { break }
      if !(first && returnAddress == link) {
        buffer[count] = returnAddress
        count += 1
      }
      first = false
      if next <= frame { break }
      frame = next
    }
    return count
  }
}

/// Serializes one record with nothing but `write(2)` and caller-owned
/// memory. The format is line-based text, read back by `SignalCrashFile`.
enum SignalCrashWriter {
  static let scratchCapacity = 32

  static func write(
    fd: Int32, signal: Int32, timeMs: Int64,
    frames: UnsafePointer<UInt64>, count: Int,
    context: UnsafePointer<UInt8>, contextLength: Int,
    scratch: UnsafeMutablePointer<UInt8>
  ) {
    put(fd, "appwin-signal 1\nsig ")
    putNumber(fd, UInt64(UInt32(bitPattern: signal)), radix: 10, scratch: scratch)
    put(fd, "\nms ")
    putNumber(fd, UInt64(max(0, timeMs)), radix: 10, scratch: scratch)
    put(fd, "\n")
    var index = 0
    while index < count {
      put(fd, "pc ")
      putNumber(fd, frames[index], radix: 16, scratch: scratch)
      put(fd, "\n")
      index += 1
    }
    put(fd, "ctx\n")
    if contextLength > 0 { _ = Darwin.write(fd, context, contextLength) }
    fsync(fd)
  }

  private static func put(_ fd: Int32, _ text: StaticString) {
    _ = Darwin.write(fd, text.utf8Start, text.utf8CodeUnitCount)
  }

  private static func putNumber(
    _ fd: Int32, _ value: UInt64, radix: UInt64, scratch: UnsafeMutablePointer<UInt8>
  ) {
    var remaining = value
    var start = scratchCapacity
    repeat {
      let digit = UInt8(truncatingIfNeeded: remaining % radix)
      start -= 1
      scratch[start] = digit < 10 ? 0x30 + digit : 0x61 + digit - 10
      remaining /= radix
    } while remaining > 0 && start > 0
    _ = Darwin.write(fd, scratch + start, scratchCapacity - start)
  }
}
