import Foundation
import Nimble
import PromiseKit
import Quick

func waitUntil(_ expression: @autoclosure @escaping () throws -> Bool,
               file: FileString = #file,
               line: UInt = #line) {
    expect(try expression(), file: file, line: line).toEventually(beTrue())
}

func waitFor<T>(_ expression: @autoclosure @escaping () throws -> T?,
                file: FileString = #file,
                line: UInt = #line) -> T? {
    expect(try expression(), file: file, line: line).toEventuallyNot(beNil())
    do {
        let result = try expression()
        return result!
    } catch {
        fail("Error thrown while retrieving value: \(error)")
        return nil
    }
}

func it(_ desc: String,
        timeout: TimeInterval = 1.0,
        failOnError: Bool = true,
        file: FileString = #file,
        line: UInt = #line,
        closure: @escaping () -> Promise<some Any>) {
    it(desc, file: file, line: line, closure: {
        let promise = closure()
        waitUntil(timeout: timeout, file: file, line: line) { done in
            promise.done { _ in
                done()
            }.catch { error in
                if failOnError {
                    fail("Promise failed with error \(error)", file: file, line: line)
                }
                done()
            }
        }
    } as () -> Void)
}

func expectToSucceed(_ promise: Promise<some Any>, file: FileString = #file, line: UInt = #line)
    -> Promise<Void> {
    promise.asVoid().recover { (error: Error) in
        fail("Expected promise to succeed, but failed with \(error)", file: file, line: line)
    }
}

func expectToFail(_ promise: Promise<some Any>, file: FileString = #file, line: UInt = #line)
    -> Promise<Void> {
    promise.asVoid().done {
        fail("Expected promise to fail, but succeeded", file: file, line: line)
    }.recover { (error: Error) -> Promise<Void> in
        expect(file, line: line, expression: { throw error }).to(throwError())
        return Promise.value(())
    }
}

func expectToFail(_ promise: Promise<some Any>,
                  with expectedError: some Error,
                  file: FileString = #file,
                  line: UInt = #line) -> Promise<Void> {
    promise.asVoid().done {
        fail("Expected promise to fail with error \(expectedError), but succeeded",
             file: file, line: line)
    }.recover { (error: Error) in
        expect(file, line: line, expression: { throw error }).to(throwError(expectedError))
    }
}

/// Convenience struct for when errors need to be thrown from tests to abort execution (e.g. during
/// a promise chain).
struct TestError: Error {
    let description: String
    init(_ description: String) { self.description = description }
}
