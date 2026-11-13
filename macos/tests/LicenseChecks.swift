import Foundation

@main
struct LicenseChecks {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { print("FAIL: \(message)"); exit(1) }
    }

    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        expect(fixture["trialDays"] as? Int == Entitlement.trialDays, "trial length")
        expect(fixture["revalidateDays"] as? Int == Entitlement.revalidateDays, "re-validation interval")
        expect(fixture["offlineGraceDays"] as? Int == Entitlement.offlineGraceDays, "offline grace")
        let iso = ISO8601DateFormatter()
        func date(_ value: Any?) -> Date? { (value as? String).flatMap(iso.date(from:)) }
        for item in fixture["cases"] as! [[String: Any]] {
            let name = item["name"] as! String
            let expectation = item["expect"] as! [String: Any]
            let license = (item["license"] as? [String: Any]).map {
                Entitlement.License(status: Entitlement.LicenseStatus(rawValue: $0["status"] as! String)!,
                                    validatedAt: date($0["validatedAt"])!)
            }
            let result = Entitlement(now: date(item["now"])!, trialStartedAt: date(item["trialStartedAt"]), license: license)
            expect(result.state.rawValue == expectation["state"] as? String, "\(name): state \(result.state)")
            expect(result.isEntitled == expectation["entitled"] as? Bool, "\(name): entitled")
            expect(result.trialDaysLeft == expectation["trialDaysLeft"] as? Int, "\(name): trial days \(String(describing: result.trialDaysLeft))")
            expect(result.shouldRevalidate == expectation["shouldRevalidate"] as? Bool, "\(name): re-validate")
        }
        let frame = Frame.peerStatus(.proEntitled).map { String(format: "%02x", $0) }.joined()
        expect(frame == fixture["peerStatusFrameHex"] as? String, "PEER_STATUS wire format \(frame)")
        let status = Frame.status([], extended: [.proEntitled, .peerStatus])
        expect(status.count == 4 && status[3] == 0b110, "STATUS extended bits for Pro and PEER_STATUS")
        print("✓ License: shared entitlement vectors, PEER_STATUS and STATUS bits")
        try checkLicenseAPI(URL(fileURLWithPath: CommandLine.arguments[2]))
    }

    /// Wspólne wektory odpowiedzi serwera licencji (tests/fixtures/license-api.json).
    static func checkLicenseAPI(_ url: URL) throws {
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let cases = fixture["cases"] as! [[String: Any]]
        for item in cases {
            let name = item["name"] as! String
            let expectation = item["expect"] as! [String: Any]
            let data = try (item["raw"] as? String).map { Data($0.utf8) }
                ?? JSONSerialization.data(withJSONObject: item["body"]!, options: [.fragmentsAllowed])
            let call = LicenseClient.Call(rawValue: item["call"] as! String)!
            do {
                let result = try LicenseClient.interpret(call, http: item["http"] as! Int, data: data,
                                                         acceptsTestLicenses: item["acceptsTest"] as! Bool,
                                                         instanceID: call == .activate ? nil : "instance")
                expect(expectation["error"] == nil, "\(name): expected \(String(describing: expectation["error"])), got \(result)")
                expect(result.status.rawValue == expectation["status"] as? String, "\(name): status \(result.status)")
                if let instance = expectation["instanceId"] as? String {
                    expect(result.instanceID == instance, "\(name): instance \(String(describing: result.instanceID))")
                }
                if expectation.keys.contains("email") || call == .validate {
                    expect(result.customerEmail == expectation["email"] as? String, "\(name): email \(String(describing: result.customerEmail))")
                }
            } catch let failure as LicenseClient.Failure {
                switch (expectation["error"] as? String, failure) {
                case ("network", .network), ("wrongProduct", .wrongProduct):
                    break
                case ("rejected", .rejected(let code, let message)):
                    expect(code == expectation["code"] as? String, "\(name): code \(String(describing: code))")
                    if let text = expectation["message"] as? String {
                        expect(failure.errorDescription == text, "\(name): message \(failure.errorDescription ?? "")")
                    } else {
                        expect(LicenseClient.Failure.message(for: code) != nil && failure.errorDescription != message,
                               "\(name): localized message for \(code ?? "nil")")
                    }
                default:
                    expect(false, "\(name): unexpected \(failure)")
                }
            }
        }
        print("✓ License API: \(cases.count) shared server response vectors")
    }
}
