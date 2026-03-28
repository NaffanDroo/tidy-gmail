import Foundation
import Quick
import Nimble
@testable import TidyGmailCore

final class KeychainServiceSpec: QuickSpec {
    override class func spec() {
        describe("LiveKeychainService") {
            var sut: LiveKeychainService!
            let testService = "com.tidygmail.tests.\(UUID().uuidString)"

            beforeEach {
                sut = LiveKeychainService(serviceName: testService)
            }

            afterEach {
                // Clean up any items written during the test.
                try? sut.delete(forKey: "test.key")
            }

            context("storing a value") {
                it("persists a string under the given key") {
                    expect { try sut.store("hello", forKey: "test.key") }.toNot(throwError())
                    let retrieved = try? sut.retrieve(forKey: "test.key")
                    expect(retrieved) == "hello"
                }

                it("overwrites an existing value without error") {
                    try? sut.store("first", forKey: "test.key")
                    expect { try sut.store("second", forKey: "test.key") }.toNot(throwError())
                    let retrieved = try? sut.retrieve(forKey: "test.key")
                    expect(retrieved) == "second"
                }
            }

            context("retrieving a value") {
                it("returns nil when the key does not exist") {
                    let result = try? sut.retrieve(forKey: "nonexistent.key")
                    expect(result).to(beNil())
                }

                it("returns the stored string") {
                    try? sut.store("stored-value", forKey: "test.key")
                    let result = try? sut.retrieve(forKey: "test.key")
                    expect(result) == "stored-value"
                }
            }

            context("deleting a value") {
                it("removes a previously stored key") {
                    try? sut.store("to-delete", forKey: "test.key")
                    expect { try sut.delete(forKey: "test.key") }.toNot(throwError())
                    let result = try? sut.retrieve(forKey: "test.key")
                    expect(result).to(beNil())
                }

                it("does not throw when the key does not exist") {
                    expect { try sut.delete(forKey: "never.stored") }.toNot(throwError())
                }
            }
        }
    }
}
