using System.Collections.ObjectModel;
using System.IO;
using System.Text.Json;

namespace F2L.Windows;

/// <summary>One message. These five fields are the whole conversation file, the same as on Mac.</summary>
public sealed class ConversationEntry
{
    private string _text = "";
    private string _status = "complete";
    public Guid TurnId { get; set; }
    public string Role { get; set; } = "assistant";
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.Now;
    public string Text { get => _text; set => _text = value ?? ""; }
    public string Status { get => _status; set => _status = value ?? "complete"; }
}

internal sealed class ConversationSession
{
    internal ObservableCollection<ConversationEntry> Entries { get; } = [];
    internal ConversationEntry Begin(string question)
    {
        var turn = Guid.NewGuid();
        Entries.Add(new ConversationEntry { Role = "user", Text = question, TurnId = turn });
        var reply = new ConversationEntry { TurnId = turn, Status = "pending", Text = "Thinking…" };
        Entries.Add(reply);
        return reply;
    }

    internal void Stop(ConversationEntry? entry)
    {
        if (entry?.Status != "pending") return;
        entry.Text = "Reply stopped. Your question is still here; you can continue below.";
        entry.Status = "stopped";
    }

    internal IReadOnlyList<(string Role, string Content)> ProviderHistory(Guid currentTurn)
    {
        var complete = Entries.Where(e => e.Role == "assistant" && e.Status == "complete" && e.TurnId != currentTurn)
            .Select(e => e.TurnId).ToHashSet();
        return Entries.Where(e => complete.Contains(e.TurnId)).TakeLast(20).Select(e => (e.Role, e.Text)).ToArray();
    }
}

internal sealed class ConversationStore(string? path = null)
{
    private readonly string _path = path ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "F2L", "conversation.json");
    private sealed record Document(int Version, List<ConversationEntry> Messages, string Draft);
    internal static ConversationStore Fresh() => new ConversationStore().NextSession();
    internal ConversationStore NextSession()
    {
        var parent = Path.GetDirectoryName(_path)!;
        var folder = Path.GetFileName(parent) == "sessions" ? parent : Path.Combine(parent, "sessions");
        return new ConversationStore(Path.Combine(folder, $"{Guid.NewGuid()}.json"));
    }

    internal string Load(ConversationSession session)
    {
        Document? document = null;
        foreach (var candidate in new[] { _path, _path + ".bak" })
        {
            try
            {
                if (File.Exists(candidate)) document = JsonSerializer.Deserialize<Document>(File.ReadAllText(candidate));
                if (document is { Version: 1 }) break;
            }
            catch (Exception error) when (error is IOException or JsonException or UnauthorizedAccessException) { }
        }
        if (document is not { Version: 1, Messages: not null }) return "";
        foreach (var entry in document.Messages.TakeLast(500).Where(entry => entry is not null && entry.Role is "user" or "assistant"))
        {
            session.Entries.Add(entry);
            session.Stop(entry);
        }
        return document.Draft ?? "";
    }

    internal bool Save(ConversationSession session, string draft)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
            var document = new Document(1, session.Entries.TakeLast(500).ToList(), draft);
            File.WriteAllText(_path + ".tmp", JsonSerializer.Serialize(document));
            if (File.Exists(_path)) File.Copy(_path, _path + ".bak", true);
            File.Move(_path + ".tmp", _path, true);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
    }
}
