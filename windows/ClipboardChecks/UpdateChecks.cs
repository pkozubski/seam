using BorderlessMouse.Net;

internal static class UpdateChecks
{
    public static void Run()
    {
        static void Expect(bool value, string message)
        {
            if (!value) throw new InvalidOperationException(message);
        }
        Expect(Updater.IsNewer("2.1.5", "2.1.4"), "installed dev 2.1.4 can upgrade");
        Expect(Updater.IsNewer("2.1.10", "2.1.9"), "dev run numbers compare numerically");
        Expect(!Updater.IsNewer("2.1.5", "2.1.5") && !Updater.IsNewer("2.1.4", "2.1.5"), "no reinstall or downgrade");
        Expect(Updater.CanAutoInstall(true, true, TimeSpan.FromSeconds(60), true), "idle dev session can restart");
        Expect(!Updater.CanAutoInstall(true, true, TimeSpan.FromSeconds(59), true), "active user cannot restart");
        Expect(!Updater.CanAutoInstall(true, true, TimeSpan.FromSeconds(120), false), "remote control or transferred windows prevent restart");
        Expect(!Updater.CanAutoInstall(true, false, TimeSpan.FromSeconds(120), true), "disabled automatic updates stay disabled");
        Expect(!Updater.CanAutoInstall(false, true, TimeSpan.FromSeconds(120), true), "stable installation stays manual");
        Console.WriteLine("✓ Updates: numeric dev versions, idle installation and active-session protection");
    }
}
