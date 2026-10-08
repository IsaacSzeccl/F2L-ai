using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace F2L.Windows;

/// <summary>Reads local provider settings, with environment and Credential Manager fallbacks.</summary>
internal static class CredentialStore
{
    private const uint GenericCredential = 1;
    private const uint PersistLocalMachine = 2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeCredential
    {
        public uint Flags;
        public uint Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    [DllImport("Advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredWrite(ref NativeCredential credential, uint flags);

    [DllImport("Advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("Advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("Advapi32.dll", EntryPoint = "CredFree")]
    private static extern void CredFree(IntPtr buffer);

    public static string Read(string name)
    {
        var environmentValue = Environment.GetEnvironmentVariable(name);
        if (!string.IsNullOrWhiteSpace(environmentValue)) return environmentValue.Trim();
        var localValue = ReadLocalSetting(name);
        if (!string.IsNullOrWhiteSpace(localValue)) return localValue.Trim();
        if (!CredRead($"F2L/{name}", GenericCredential, 0, out var pointer)) return "";
        try
        {
            var credential = Marshal.PtrToStructure<NativeCredential>(pointer);
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0) return "";
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.Unicode.GetString(bytes).TrimEnd('\0');
        }
        finally { CredFree(pointer); }
    }

    /// <summary>A plain text setting such as "Provider": the environment variable first, then local.settings.json.</summary>
    internal static string ReadText(string variable, string property)
    {
        var environmentValue = Environment.GetEnvironmentVariable(variable);
        return !string.IsNullOrWhiteSpace(environmentValue) ? environmentValue.Trim() : ReadProperty(property).Trim();
    }

    private static string ReadLocalSetting(string name)
    {
        var propertyName = name == "ELEVENLABS_API_KEY" ? "ElevenLabsApiKey"
            : Providers.All.Where(provider => provider.KeyVariable() == name).Select(provider => provider.KeyProperty()).FirstOrDefault() ?? "";
        return ReadProperty(propertyName);
    }

    private static string ReadProperty(string propertyName)
    {
        var settingsPath = FindLocalSettingsPath();
        if (propertyName.Length == 0 || !File.Exists(settingsPath)) return "";

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(settingsPath));
            return document.RootElement.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.String
                ? value.GetString() ?? ""
                : "";
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException)
        {
            return ""; // InvalidOperationException: the file holds JSON that isn't an object
        }
    }

    /// <summary>
    /// Same search order as the Mac app (Sources/CoachCore/LocalSettings.swift): the per-user settings file, then the
    /// F2L folder the app was built from (repository-root local.settings.json, or the older Windows/F2L.Windows copy),
    /// then the copy next to the executable. When none exists, the per-user path is where a new file belongs.
    /// A Windows folder copied without the rest of F2L still finds the copy beside F2L.Windows.csproj.
    /// </summary>
    internal static string FindLocalSettingsPath()
    {
        var user = UserSettingsPath;
        if (File.Exists(user)) return user;
        string? projectCopy = null;
        for (DirectoryInfo? directory = new(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var settings = Path.Combine(directory.FullName, "local.settings.json");
            if (projectCopy is null && File.Exists(Path.Combine(directory.FullName, "F2L.Windows.csproj")) && File.Exists(settings))
                projectCopy = settings;
            if (!File.Exists(Path.Combine(directory.FullName, "Package.swift"))) continue;
            foreach (var candidate in new[] { settings, Path.Combine(directory.FullName, "Windows", "F2L.Windows", "local.settings.json") })
                if (File.Exists(candidate)) return candidate;
        }
        if (projectCopy is not null) return projectCopy;
        var beside = Path.Combine(AppContext.BaseDirectory, "local.settings.json");
        return File.Exists(beside) ? beside : user;
    }

    internal static string UserSettingsPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "F2L", "local.settings.json");

    /// <summary>Every field a new settings file starts with, all empty except the provider. Same as LocalSettings.template.</summary>
    internal static string Template => "{\n" + string.Join(",\n", new[] { "  \"Provider\": \"deepseek\"" }.Concat(Providers.All.SelectMany(provider =>
        new[] { $"  \"{provider.KeyProperty()}\": \"\"", $"  \"{provider.ModelProperty()}\": \"\"" }))) + "\n}\n";

    /// <summary>Writes the chosen provider into the settings file in use (creating it), keeping every key.</summary>
    internal static bool SetProvider(Provider provider)
    {
        var path = PrepareSettingsFile();
        try
        {
            var settings = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(path)) as System.Text.Json.Nodes.JsonObject ?? new();
            settings["Provider"] = provider.Id();
            File.WriteAllText(path, settings.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            return true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException) { return false; }
    }

    /// <summary>Creates an empty settings file to fill in, if none exists yet, and returns the file to show.</summary>
    internal static string PrepareSettingsFile()
    {
        var path = FindLocalSettingsPath();
        if (File.Exists(path)) return path;
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            using var file = new FileStream(path, FileMode.CreateNew);
            file.Write(Encoding.UTF8.GetBytes(Template));
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        return path;
    }

    public static void Write(string name, string value)
    {
        var target = $"F2L/{name}";
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            CredDelete(target, GenericCredential, 0);
            return;
        }

        var targetPointer = Marshal.StringToHGlobalUni(target);
        var userPointer = Marshal.StringToHGlobalUni(Environment.UserName);
        var bytes = Encoding.Unicode.GetBytes(trimmed);
        var blobPointer = Marshal.AllocHGlobal(bytes.Length);
        try
        {
            Marshal.Copy(bytes, 0, blobPointer, bytes.Length);
            var credential = new NativeCredential
            {
                Type = GenericCredential,
                TargetName = targetPointer,
                UserName = userPointer,
                CredentialBlob = blobPointer,
                CredentialBlobSize = (uint)bytes.Length,
                Persist = PersistLocalMachine,
            };
            if (!CredWrite(ref credential, 0)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        finally
        {
            Marshal.FreeHGlobal(targetPointer);
            Marshal.FreeHGlobal(userPointer);
            Marshal.Copy(new byte[bytes.Length], 0, blobPointer, bytes.Length);
            Marshal.FreeHGlobal(blobPointer);
            Array.Clear(bytes);
        }
    }
}
