using System.Text.Json;
using Seam.Licensing;
using Seam.Protocol;

/// <summary>Wspólne wektory modelu uprawnień Pro (tests/fixtures/entitlement.json) i ramki licencji.</summary>
internal static class LicenseChecks
{
    public static void Run()
    {
        using var fixture = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "entitlement.json")));
        var root = fixture.RootElement;
        Expect(root.GetProperty("trialDays").GetInt32() == Entitlement.TrialDays, "trial length");
        Expect(root.GetProperty("revalidateDays").GetInt32() == Entitlement.RevalidateDays, "re-validation interval");
        Expect(root.GetProperty("offlineGraceDays").GetInt32() == Entitlement.OfflineGraceDays, "offline grace");
        foreach (var item in root.GetProperty("cases").EnumerateArray())
        {
            var name = item.GetProperty("name").GetString();
            var expect = item.GetProperty("expect");
            LicenseSnapshot? license = item.GetProperty("license").ValueKind == JsonValueKind.Object
                ? new(Enum.Parse<LicenseStatus>(item.GetProperty("license").GetProperty("status").GetString()!, true),
                      Date(item.GetProperty("license").GetProperty("validatedAt"))!.Value)
                : null;
            var result = Entitlement.Evaluate(Date(item.GetProperty("now"))!.Value, Date(item.GetProperty("trialStartedAt")), license);
            var state = expect.GetProperty("state").GetString()!;
            Expect(string.Equals(result.State.ToString(), state, StringComparison.OrdinalIgnoreCase), $"{name}: state {result.State}");
            Expect(result.IsEntitled == expect.GetProperty("entitled").GetBoolean(), $"{name}: entitled");
            int? days = expect.GetProperty("trialDaysLeft").ValueKind == JsonValueKind.Number ? expect.GetProperty("trialDaysLeft").GetInt32() : null;
            Expect(result.TrialDaysLeft == days, $"{name}: trial days {result.TrialDaysLeft}");
            Expect(result.ShouldRevalidate == expect.GetProperty("shouldRevalidate").GetBoolean(), $"{name}: re-validate");
        }
        var frame = Convert.ToHexString(Frame.PeerStatus(PeerStatusFlags.ProEntitled));
        Expect(frame.Equals(root.GetProperty("peerStatusFrameHex").GetString(), StringComparison.OrdinalIgnoreCase), $"PEER_STATUS wire format {frame}");
        Expect((byte)(ExtendedStatusFlags.ProEntitled | ExtendedStatusFlags.PeerStatus) == 0b110, "STATUS extended bits for Pro and PEER_STATUS");
        Console.WriteLine("✓ License: shared entitlement vectors, PEER_STATUS and STATUS bits");
    }

    private static DateTimeOffset? Date(JsonElement value) =>
        value.ValueKind == JsonValueKind.String ? DateTimeOffset.Parse(value.GetString()!, System.Globalization.CultureInfo.InvariantCulture) : null;

    private static void Expect(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
