using System.Text.Json;
using VoiSER.Windows.Core;

namespace VoiSER.Windows.Infrastructure;

public sealed class JsonSettingsStore : ISettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
    };

    private readonly string _settingsPath;

    public JsonSettingsStore(string? settingsPath = null)
    {
        _settingsPath = settingsPath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "VoiSER",
            "settings.json"
        );
    }

    public async Task<AppSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(_settingsPath))
        {
            return new AppSettings();
        }

        try
        {
            await using var stream = File.OpenRead(_settingsPath);
            var settings = await JsonSerializer.DeserializeAsync<AppSettings>(stream, JsonOptions, cancellationToken);
            return settings ?? new AppSettings();
        }
        catch (JsonException)
        {
            TryBackupCorruptedSettings();
            return new AppSettings();
        }
        catch (IOException)
        {
            TryBackupCorruptedSettings();
            return new AppSettings();
        }
        catch (UnauthorizedAccessException)
        {
            TryBackupCorruptedSettings();
            return new AppSettings();
        }
    }

    public async Task SaveAsync(AppSettings settings, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_settingsPath)!);
        await using var stream = File.Create(_settingsPath);
        await JsonSerializer.SerializeAsync(stream, settings, JsonOptions, cancellationToken);
    }

    private void TryBackupCorruptedSettings()
    {
        try
        {
            if (!File.Exists(_settingsPath))
            {
                return;
            }

            var backupPath = $"{_settingsPath}.corrupt-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}.json";
            File.Copy(_settingsPath, backupPath, overwrite: true);
        }
        catch
        {
            // Backup is best effort only.
        }
    }
}
