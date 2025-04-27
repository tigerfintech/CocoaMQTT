//
//  MQTTTests.swift
//  CocoaMQTT
//
//  Created by hujinyou on 2025/4/27.
//

import XCTest
@testable import CocoaMQTT

final class MQTTTests: XCTestCase {

    class TimerWrapper {
        var timer: CocoaMQTTTimer? = CocoaMQTTTimer(delay: 10, name: "crashTimer", timeInterval: 0)
    }

    func testDeinitWithoutResumeTriggersCrash() {
        let expectation = self.expectation(description: "Timer should crash")

        // 创建多个定时器，并用循环同时操作多个定时器
        var timers: [CocoaMQTTTimer] = []
        for i in 0..<10 {
            let timer = CocoaMQTTTimer(name: "TestTimer\(i)", timeInterval: 0.1)

            // 让定时器进入暂停状态
            timer.suspend()

            // 给定时器一个回调，并在回调中进行取消操作
            timer.eventHandler = { [weak timer] in
                guard let timer = timer else { return }
                // 模拟多次暂停和取消定时器
                if i % 2 == 0 {
                    timer.suspend()
                    timer.cancel()
                    print("Timer \(i) suspended and cancelled")
                } else {
                    timer.resume()
                    timer.cancel()
                    print("Timer \(i) resumed and cancelled")
                }
            }

            print("Timer \(i) created")
            timers.append(timer)

            // 手动触发定时器，使其开始工作
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(i) * 0.05) {
                print("Timer \(i) started")
                timer.resume()
            }
        }

        // 等待一定的时间，让定时器操作完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            print("All timers should be cancelled")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5)
    }
}


final class CocoaMQTTTimerTests: XCTestCase {

    /// 测试反复创建和销毁 Timer，验证是否会因 suspend 状态下 cancel 崩溃
    func testRapidCreateAndDestroy() {
        for i in 0..<1000 {
            let timer = CocoaMQTTTimer(delay: 0.1, name: "timer-\(i)", timeInterval: 0)
            timer.eventHandler = {
                // no-op
            }
            // 不 resume，直接释放 -> 验证 deinit 能否避免 crash
        }
    }

    /// 测试 Timer 在 resume 后销毁
    func testResumeThenDeinit() {
        for i in 0..<1000 {
            let timer = CocoaMQTTTimer(delay: 0.1, name: "resume-\(i)", timeInterval: 0)
            timer.eventHandler = { }
            timer.resume()
        }
    }

    /// 测试 Timer 在 resume -> suspend -> resume -> cancel 多次操作后释放
    func testRepeatedResumeSuspendCancel() {
        for i in 0..<1000 {
            let timer = CocoaMQTTTimer(delay: 0.1, name: "bounce-\(i)", timeInterval: 1.0)
            timer.eventHandler = { }

            timer.resume()
            timer.suspend()
            timer.resume()
            timer.cancel()
        }
    }

    /// 验证 after 模式不会 crash，自动执行一次后释放
    func testAfterExecutesSafely() {
        let expectation = expectation(description: "after block executed")
        let timer = CocoaMQTTTimer.after(0.5, name: "after-test") {
            expectation.fulfill()
        }
        XCTAssertNotNil(timer)
        wait(for: [expectation], timeout: 1.0)
    }

    /// 多线程并发创建/销毁 Timer，验证线程安全
    func testConcurrentTimerLifecycle() {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.concurrent.queue", attributes: .concurrent)

        for i in 0..<1000 {
            group.enter()
            queue.async {
                let timer = CocoaMQTTTimer(delay: 0.1, name: "concurrent-\(i)", timeInterval: 0.2)
                timer.eventHandler = { }
                timer.resume()
                timer.suspend()
                timer.cancel()
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5)
        XCTAssertEqual(result, .success)
    }

    /// Timer 在 handler 内部立即 suspend 自己，确保不影响后续 deinit
    func testSuspendInsideHandler() {
        let expectation = expectation(description: "handler executed")
        var timer: CocoaMQTTTimer? = CocoaMQTTTimer(name: "suspend-inside", timeInterval: 0.1)
        timer?.eventHandler = {
            timer?.suspend()
            timer = nil
            expectation.fulfill()
        }
        timer?.resume()

        wait(for: [expectation], timeout: 1.0)
    }
}
