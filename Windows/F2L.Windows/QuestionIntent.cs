using System.Text.RegularExpressions;

namespace F2L.Windows;

public enum QuestionIntent
{
    QuickFact,
    Procedural,
    MultiPart,
    ClarificationNeeded,
}

public static partial class QuestionIntentClassifier
{
    [GeneratedRegex(@"\b(which one|can you help with this|help me with this|what about that|do you mean|not sure which|this one)\b", RegexOptions.IgnoreCase)]
    private static partial Regex AmbiguousPattern();

    [GeneratedRegex(@"\b(compare|difference between|explain .+ and|both .+ and|all the steps|why .+ when|what happens if)\b", RegexOptions.IgnoreCase)]
    private static partial Regex MultiPartPattern();

    [GeneratedRegex(@"\b(how (do|can|to)|where (do|is)|show me|step by step|click|select|open|add these|enter a formula)\b", RegexOptions.IgnoreCase)]
    private static partial Regex ProceduralPattern();

    [GeneratedRegex(@"\b(hello|hi|hey|what is|what does|define|meaning of|what's a|who is|when did|how many)\b", RegexOptions.IgnoreCase)]
    private static partial Regex QuickFactPattern();

    public static QuestionIntent Classify(string question)
    {
        var text = question.Trim();
        if (AmbiguousPattern().IsMatch(text))
            return QuestionIntent.ClarificationNeeded;
        if (MultiPartPattern().IsMatch(text) || text.Count(character => character == '?') > 1)
            return QuestionIntent.MultiPart;
        if (ProceduralPattern().IsMatch(text))
            return QuestionIntent.Procedural;
        if (QuickFactPattern().IsMatch(text))
            return QuestionIntent.QuickFact;
        return QuestionIntent.Procedural;
    }
}
