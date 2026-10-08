using System.Diagnostics;
using System.IO;
using System.Windows;

namespace F2L.Windows;

/// <summary>Mirrors Sources/F2L/SettingsWindow.swift: which AI is used, where keys live, and what is stored.</summary>
public partial class SettingsWindow : Window
{
    public SettingsWindow()
    {
        InitializeComponent();
        var path = CredentialStore.FindLocalSettingsPath();
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        SettingsPath.Text = path.StartsWith(home, StringComparison.OrdinalIgnoreCase) ? "~" + path[home.Length..] : path;
        var current = CoachSettings.Current();
        ProviderText.Text = $"{current.Provider.Name()} · {current.Model}{(string.IsNullOrWhiteSpace(current.ApiKey) ? " · no key yet" : "")}";
    }

    // Creates an empty file to fill in when there isn't one yet, then shows it in File Explorer.
    private void ShowFile_Click(object sender, RoutedEventArgs e)
    {
        var path = CredentialStore.PrepareSettingsFile();
        if (File.Exists(path)) Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{path}\"") { UseShellExecute = true });
        else Process.Start(new ProcessStartInfo("explorer.exe", $"\"{Path.GetDirectoryName(path)}\"") { UseShellExecute = true });
    }

    private void Done_Click(object sender, RoutedEventArgs e) => Close();
}
