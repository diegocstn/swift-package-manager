/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Commands
import PackageModel
import SPMTestSupport
import TSCBasic
import Workspace
import XCTest

class BuildPerfTests: XCTestCasePerf {

    @discardableResult
    func execute(args: [String] = [], packagePath: AbsolutePath) throws -> (stdout: String, stderr: String) {
        // FIXME: We should pass the SWIFT_EXEC at lower level.
        return try SwiftPMProduct.SwiftBuild.execute(args + [], packagePath: packagePath, env: ["SWIFT_EXEC": ToolchainConfiguration.default.swiftCompilerPath.pathString])
    }

    func clean(packagePath: AbsolutePath) throws {
        _ = try SwiftPMProduct.SwiftPackage.execute(["clean"], packagePath: packagePath)
    }

    func testTrivialPackageFullBuild() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try runFullBuildTest(for: "DependencyResolution/Internal/Simple", product: "foo")
    }

    func testTrivialPackageNullBuild() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try runNullBuildTest(for: "DependencyResolution/Internal/Simple", product: "foo")
    }

    func testComplexPackageFullBuild() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try runFullBuildTest(for: "DependencyResolution/External/Complex", app: "app", product: "Dealer")
    }

    func testComplexPackageNullBuild() throws {
        #if !os(macOS)
        try XCTSkipIf(true, "test is only supported on macOS")
        #endif
        try runNullBuildTest(for: "DependencyResolution/External/Complex", app: "app", product: "Dealer")
    }

    func runFullBuildTest(for name: String, app appString: String? = nil, product productString: String) throws {
        try fixture(name: name) { fixturePath in
            let app = fixturePath.appending(components: (appString ?? ""))
            let triple = UserToolchain.default.triple
            let product = app.appending(components: ".build", triple.platformBuildPathComponent(), "debug", productString)
            try self.execute(packagePath: app)
            measure {
                try! self.clean(packagePath: app)
                try! self.execute(packagePath: app)
                XCTAssertFileExists(product)
            }
        }
    }

    func runNullBuildTest(for name: String, app appString: String? = nil, product productString: String) throws {
        try fixture(name: name) { fixturePath in
            let app = fixturePath.appending(components: (appString ?? ""))
            let triple = UserToolchain.default.triple
            let product = app.appending(components: ".build", triple.platformBuildPathComponent(), "debug", productString)
            try self.execute(packagePath: app)
            measure {
                try! self.execute(packagePath: app)
                XCTAssertFileExists(product)
            }
        }
    }
}
