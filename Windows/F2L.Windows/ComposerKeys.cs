using System.Windows.Input;

namespace F2L.Windows;

internal static class ComposerKeys
{
    internal static bool ShouldSend(Key key, ModifierKeys modifiers, bool composing) =>
        key == Key.Enter && (modifiers & ModifierKeys.Shift) == 0 && !composing;
}
