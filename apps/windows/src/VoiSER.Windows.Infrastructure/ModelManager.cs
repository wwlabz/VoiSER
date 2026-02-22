using VoiSER.Windows.Core;

namespace VoiSER.Windows.Infrastructure;

public sealed class ModelManager : IModelManager
{
    private static readonly HttpClient Http = new();

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

        var markerFile = Path.Combine(dir, ".model-ready");
        if (File.Exists(markerFile))
        {
            progress?.Report((1, "Model ready"));
            return;
        }

        progress?.Report((0.1, "Preparing local model directory"));

        // Placeholder bootstrap for v1 structure.
        // Real model composition/weights can be added without changing app contracts.
        var readmePath = Path.Combine(dir, "README.txt");
        await File.WriteAllTextAsync(readmePath,
            "Model bootstrap placeholder. Integrate full whisper.cpp model assets in packaging pipeline.",
            cancellationToken);

        await File.WriteAllTextAsync(markerFile, DateTimeOffset.UtcNow.ToString("O"), cancellationToken);
        progress?.Report((1, "Model ready"));
    }
}
