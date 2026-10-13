using System.Globalization;
using System.Speech.Recognition;
using System.Text;

namespace F2L.Windows;

internal sealed class PushToTalkInput : IDisposable
{
    private readonly object _gate = new();
    private SpeechRecognitionEngine? _engine;
    private TaskCompletionSource<string>? _stopped;
    private readonly StringBuilder _transcript = new();
    private string _hypothesis = "";

    public event Action<string>? TranscriptChanged;
    public event Action<string>? RecognitionFailed;
    public bool IsListening => _engine is not null;
    public string RecognizerLanguage { get; private set; } = "";

    public bool Start(out string error)
    {
        error = "";
        if (_engine is not null) Cancel();
        try
        {
            lock (_gate)
            {
                _transcript.Clear();
                _hypothesis = "";
            }
            var engine = CreateRecognizer(out var selectedLanguage);
            RecognizerLanguage = selectedLanguage;
            _engine = engine;
            engine.LoadGrammar(new DictationGrammar());
            engine.SetInputToDefaultAudioDevice();
            engine.SpeechHypothesized += OnHypothesized;
            engine.SpeechRecognized += OnRecognized;
            engine.RecognizeCompleted += OnCompleted;
            engine.RecognizeAsync(RecognizeMode.Multiple);
            return true;
        }
        catch (Exception exception)
        {
            error = exception.Message;
            Cancel();
            return false;
        }
    }

    public async Task<string> StopAsync()
    {
        var engine = _engine;
        if (engine is null) return CurrentTranscript;
        var completion = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        _stopped = completion;
        try
        {
            engine.RecognizeAsyncStop();
            return await completion.Task.WaitAsync(TimeSpan.FromSeconds(2));
        }
        catch (TimeoutException)
        {
            engine.RecognizeAsyncCancel();
            return CurrentTranscript;
        }
        catch (InvalidOperationException)
        {
            return CurrentTranscript;
        }
        finally
        {
            _stopped = null;
            DisposeEngine(engine);
        }
    }

    public void Cancel()
    {
        var engine = _engine;
        if (engine is null) return;
        try { engine.RecognizeAsyncCancel(); } catch (InvalidOperationException) { }
        _stopped?.TrySetCanceled();
        DisposeEngine(engine);
    }

    private string CurrentTranscript
    {
        get { lock (_gate) return JoinTranscript(_transcript.ToString(), _hypothesis).Trim(); }
    }

    private static SpeechRecognitionEngine CreateRecognizer(out string selectedLanguage)
    {
        var preferred = CultureInfo.CurrentUICulture;
        var installed = SpeechRecognitionEngine.InstalledRecognizers();
        var match = installed.FirstOrDefault(recognizer =>
            string.Equals(recognizer.Culture.Name, preferred.Name, StringComparison.OrdinalIgnoreCase))
            ?? installed.FirstOrDefault(recognizer =>
                string.Equals(recognizer.Culture.TwoLetterISOLanguageName, preferred.TwoLetterISOLanguageName, StringComparison.OrdinalIgnoreCase));
        if (match is not null)
        {
            selectedLanguage = match.Culture.NativeName;
            return new SpeechRecognitionEngine(match);
        }

        var engine = new SpeechRecognitionEngine();
        selectedLanguage = engine.RecognizerInfo.Culture.NativeName;
        return engine;
    }

    private void OnHypothesized(object? sender, SpeechHypothesizedEventArgs eventArgs)
    {
        string transcript;
        lock (_gate)
        {
            _hypothesis = eventArgs.Result.Text;
            transcript = JoinTranscript(_transcript.ToString(), _hypothesis);
        }
        TranscriptChanged?.Invoke(transcript);
    }

    private void OnRecognized(object? sender, SpeechRecognizedEventArgs eventArgs)
    {
        if (eventArgs.Result.Confidence < 0.25) return;
        string transcript;
        lock (_gate)
        {
            AppendRecognizedText(eventArgs.Result.Text);
            _hypothesis = "";
            transcript = _transcript.ToString().Trim();
        }
        TranscriptChanged?.Invoke(transcript);
    }

    private void OnCompleted(object? sender, RecognizeCompletedEventArgs eventArgs)
    {
        if (eventArgs.Error is not null) RecognitionFailed?.Invoke(eventArgs.Error.Message);
        _stopped?.TrySetResult(CurrentTranscript);
    }

    private void AppendRecognizedText(string text)
    {
        var clean = text.Trim();
        if (clean.Length == 0) return;
        if (_transcript.Length > 0 && !char.IsPunctuation(clean[0])) _transcript.Append(' ');
        _transcript.Append(clean);
    }

    private static string JoinTranscript(string committed, string hypothesis)
    {
        if (string.IsNullOrWhiteSpace(hypothesis)) return committed;
        if (string.IsNullOrWhiteSpace(committed)) return hypothesis;
        var clean = hypothesis.TrimStart();
        return char.IsPunctuation(clean[0]) ? committed + clean : committed + " " + clean;
    }

    private void DisposeEngine(SpeechRecognitionEngine engine)
    {
        if (ReferenceEquals(_engine, engine)) _engine = null;
        engine.SpeechHypothesized -= OnHypothesized;
        engine.SpeechRecognized -= OnRecognized;
        engine.RecognizeCompleted -= OnCompleted;
        engine.Dispose();
    }

    public void Dispose() => Cancel();
}
