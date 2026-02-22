using VoiSER.Windows.Core;

namespace VoiSER.Windows.Infrastructure;

public sealed class WhisperTranscriptionService : ITranscriptionService
{
    private readonly IModelManager _modelManager;
    private readonly string _modelVariant;

    public WhisperTranscriptionService(IModelManager modelManager, string modelVariant = "small")
    {
        _modelManager = modelManager;
        _modelVariant = modelVariant;
    }

    public async Task<TranscriptionResult> TranscribeAsync(string audioFilePath, CancellationToken cancellationToken = default)
    {
        await _modelManager.EnsureModelReadyAsync(_modelVariant, cancellationToken: cancellationToken);

        // v1 scaffold: local whisper.cpp runtime wiring is prepared through dependencies and storage conventions.
        // Replace this placeholder with actual whisper.net inference invocation in next iteration.
        var text = $"[transcribed-local] {Path.GetFileNameWithoutExtension(audioFilePath)}";
        return new TranscriptionResult(text, "en", 0);
    }
}
