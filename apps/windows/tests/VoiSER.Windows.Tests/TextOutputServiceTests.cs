using VoiSER.Windows.Core;
using VoiSER.Windows.Infrastructure;

namespace VoiSER.Windows.Tests;

public sealed class TextOutputServiceTests
{
    private sealed class InMemoryClipboard : IClipboardClient
    {
        public string Value { get; private set; } = string.Empty;

        public Task SetTextAsync(string text, CancellationToken cancellationToken = default)
        {
            Value = text;
            return Task.CompletedTask;
        }
    }

    [Fact]
    public async Task ClipboardModeCopiesText()
    {
        var clipboard = new InMemoryClipboard();
        var service = new TextOutputService(clipboard);

        var outcome = await service.DeliverAsync("hello", TextOutputMode.Clipboard);

        Assert.Equal("hello", clipboard.Value);
        Assert.Equal(TextDeliveryKind.CopiedToClipboard, outcome.Kind);
        Assert.Equal(TextOutputFallbackReason.ExplicitClipboardMode, outcome.FallbackReason);
    }
}
