//
//  CocoaMQTTTimer.swift
//  CocoaMQTT
//
//  Contributed by Jens(https://github.com/jmiltner)
//
//  Copyright © 2019 emqx.io. All rights reserved.
//

import Foundation

/// CocoaMQTT 内部使用的 GCD Timer 实现，避免重复 resume 或 suspend 导致的崩溃。
/// 支持 `.after` 和 `.every` 两种使用方式，兼顾线程安全与状态管理。
final class CocoaMQTTTimer {

    /// 定时任务间隔
    let timeInterval: TimeInterval

    /// 初次启动延迟时间
    let startDelay: TimeInterval

    /// 当前 timer 的唯一名称（用于标识调试）
    let name: String

    /// Timer 执行所在队列（串行，目标为共享并发队列）
    private let queue: DispatchQueue

    /// 具体使用的 GCD 定时器对象
    private let timer: DispatchSourceTimer

    /// 用户设置的回调事件
    var eventHandler: (() -> Void)?

    /// 定时器状态（避免重复 resume/cancel）
    private enum State {
        case suspended
        case resumed
        case canceled
    }

    /// 当前状态（默认 suspended）
    private var state: State = .suspended

    /// 用于同步状态访问的互斥锁
    private let lock = NSLock()

    /// 初始化定时器（不自动启动）
    /// - Parameters:
    ///   - delay: 初次启动延迟
    ///   - name: timer 名称
    ///   - timeInterval: 循环时间间隔（为 0 则只执行一次）
    init(delay: TimeInterval? = nil, name: String, timeInterval: TimeInterval) {
        self.name = name
        self.timeInterval = timeInterval
        self.startDelay = delay ?? timeInterval

        // 使用串行队列执行任务，挂靠在 CocoaMQTT 的共享并发队列上
        self.queue = DispatchQueue(label: "io.emqx.CocoaMQTT.\(name)", target: CocoaMQTTTimer.targetQueue)
        self.timer = DispatchSource.makeTimerSource(flags: .strict, queue: self.queue)

        // 配置定时器调度策略
        self.timer.schedule(
            deadline: .now() + self.startDelay,
            repeating: self.timeInterval > 0 ? self.timeInterval : .infinity
        )

        // 设置回调逻辑
        self.timer.setEventHandler { [weak self] in
            self?.eventHandler?()
        }
    }

    /// 销毁时：确保事件清空 + 状态一致性 + 避免崩溃
    deinit {
        lock.lock()

        // 清空回调，防止持有
        timer.setEventHandler {}

        // 防止崩溃：如果是 suspended 状态，必须 resume 后再 cancel
        if state == .suspended {
            timer.resume()
        }

        state = .canceled
        timer.cancel()
        eventHandler = nil

        lock.unlock()
    }

    /// 开始执行定时任务（只能调用一次）
    func resume() {
        lock.lock()
        defer { lock.unlock() }

        guard state == .suspended else { return }

        state = .resumed
        timer.resume()
    }

    /// 暂停定时任务
    func suspend() {
        lock.lock()
        defer { lock.unlock() }

        guard state == .resumed else { return }

        state = .suspended
        timer.suspend()
    }

    /// 取消定时器
    func cancel() {
        lock.lock()
        defer { lock.unlock() }

        guard state != .canceled else { return }

        if state == .suspended {
            timer.resume() // 必须 resume 后才能 cancel
        }

        state = .canceled
        timer.cancel()
    }

    /// CocoaMQTT 内部定时任务共享并发队列
    private static let targetQueue = DispatchQueue(
        label: "io.emqx.CocoaMQTT.TimerQueue",
        qos: .default,
        attributes: .concurrent
    )

    /// 快速创建一个循环执行的定时器
    /// - Parameters:
    ///   - interval: 间隔时间
    ///   - name: 标识名称
    ///   - block: 要执行的事件
    class func every(_ interval: TimeInterval, name: String, _ block: @escaping () -> Void) -> CocoaMQTTTimer {
        let timer = CocoaMQTTTimer(name: name, timeInterval: interval)
        timer.eventHandler = block
        timer.resume()
        return timer
    }

    /// 快速创建一个只执行一次的定时器
    /// - Parameters:
    ///   - interval: 延迟时间
    ///   - name: 标识名称
    ///   - block: 要执行的事件
    @discardableResult
    class func after(_ interval: TimeInterval, name: String, _ block: @escaping () -> Void) -> CocoaMQTTTimer {
        let timer = CocoaMQTTTimer(delay: interval, name: name, timeInterval: 0)
        timer.eventHandler = { [weak timer] in
            block()
            timer?.suspend()
        }
        timer.resume()
        return timer
    }
}
