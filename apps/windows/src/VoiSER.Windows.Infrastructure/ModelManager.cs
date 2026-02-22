using Whisper.net.Ggml;
using VoiSER.Windows.Core;

namespace VoiSER.Windows.Infrastructure;

public sealed class ModelManager : IModelManager
{
    public string ModelDirectory(string variant)
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VoiSER",
            "Models",
            variant
        );
    }

    public async Task EnsureModelReadyAsync(string variant, IProgress<(double Progress, string Message)>? progress = null, CancellationToken cancellationToken = default)
    {
        var dir = ModelDirectory(variant);
        Directory.CreateDirectory(dir);

        var modelFile = Path.Combine(dir, ModelFileName(variant));
        if (File.Exists(modelFile))
        {
            progress?.Report((1, "Модель готова"));
            return;
        }

        progress?.Report((0.05, "Подготовка загрузки модели"));

        var ggmlType = ModelType(variant);
        await using var modelStream = await WhisperGgmlDownloader.Default.GetGgmlModelAsync(ggmlType);

        progress?.Report((0.2, "Загрузка локальной модели Whisper"));

        await using var fileWriter = File.OpenWrite(modelFile);
        await modelStream.CopyToAsync(fileWriter, cancellationToken);
        await fileWriter.FlushAsync(cancellationToken);

        progress?.Report((1, "Модель готова"));
    }

    private static GgmlType ModelType(string variant)
    {
        return variant.ToLowerInvariant() switch
        {
            "tiny" => GgmlType.Tiny,
            "base" => GgmlType.Base,
            "small" => GgmlType.Small,
            "medium" => GgmlType.Medium,
            "large" => GgmlType.Large,
            _ => GgmlType.Small,
        };
    }

    private static string ModelFileName(string variant)
    {
        var suffix = variant.ToLowerInvariant() switch
        {
            "tiny" => "tiny",
            "base" => "base",
            "small" => "small",
            "medium" => "medium",
            "large" => "large",
            _ => "small",
        };

        return $"ggml-{suffix}.bin";
    }
}
