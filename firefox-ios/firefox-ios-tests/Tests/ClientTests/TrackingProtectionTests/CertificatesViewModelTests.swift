// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import XCTest
import X509
@testable import Client

final class CertificatesViewModelTests: XCTestCase {
    private var viewModel: CertificatesViewModel!

    override func setUp() {
        super.setUp()
        viewModel = CertificatesViewModel(topLevelDomain: "topLevelDomainTest.com",
                                          title: "TitleTest",
                                          URL: "https://google.com",
                                          certificates: [])
    }

    override func tearDown() {
        super.tearDown()
        viewModel = nil
    }

    func testGetCertificateValues() {
        let data = "CN=www.google.com, O=Google Trust Services, C=US"
        let result = viewModel.getCertificateValues(from: data)
        XCTAssertEqual(result["CN"], "www.google.com")
        XCTAssertEqual(result["O"], "Google Trust Services")
        XCTAssertEqual(result["C"], "US")
    }

    func testGetCertificateFromInvalidData() {
        let result = viewModel.getCertificateValues(from: "")
        XCTAssertEqual(result, [:])
    }

    func testGetCertificateValuesWithMissingValue() {
        let data = "CN=www.google.com, O=, C=US"
        let result = viewModel.getCertificateValues(from: data)
        XCTAssertEqual(result["CN"], "www.google.com")
        XCTAssertEqual(result["O"], "")
        XCTAssertEqual(result["C"], "US")
    }

    func testGetDNSNamesList() {
        let input = #"DNSName("www.google.com"), DNSName("*www.google.com")"#
        let result = viewModel.getDNSNamesList(from: input)
        XCTAssertEqual(result, ["www.google.com", "*www.google.com"])
    }

    func testGetDNSNamesFromInvalidInput() {
        let result = viewModel.getDNSNamesList(from: "")
        XCTAssertEqual(result, [])
    }
}
