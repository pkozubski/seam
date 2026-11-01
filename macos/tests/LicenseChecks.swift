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
    }
}
