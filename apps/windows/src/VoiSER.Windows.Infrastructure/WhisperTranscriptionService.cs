using Whisper.net;
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

        var modelPath = Path.Combine(_modelManager.ModelDirectory(_modelVariant), $"ggml-{_modelVariant.ToLowerInvariant()}.bin");
        if (!File.Exists(modelPath))
        {
            throw new FileNotFoundException("Whisper model file missing", modelPath);
        }

        using var whisperFactory = WhisperFactory.FromPath(modelPath);
        using var processor = whisperFactory.CreateBuilder()
            .WithLanguage("auto")
            .Build();

        await using var fileStream = File.OpenRead(audioFilePath);

        var segments = new List<string>();
        await foreach (var result in processor.ProcessAsync(fileStream, cancellationToken))
        {
            if (!string.IsNullOrWhiteSpace(result.Text))
            {
                segments.Add(result.Text.Trim());
            }
        }

        var text = string.Join(" ", segments).Trim();
        return new TranscriptionResult(text, "auto", 0);
    }
}
