using NAudio.Wave;
using VoiSER.Windows.Core;

namespace VoiSER.Windows.Infrastructure;

public sealed class NAudioCaptureService : IAudioCaptureService
{
    private WaveInEvent? _waveIn;
    private WaveFileWriter? _writer;
    private string? _currentFilePath;

    public Task StartAsync(CancellationToken cancellationToken = default)
    {
        if (_waveIn is not null)
        {
            return Task.CompletedTask;
        }

        var recordingsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "VoiSER",
            "Recordings"
        );
        Directory.CreateDirectory(recordingsDir);

        _currentFilePath = Path.Combine(recordingsDir, $"capture-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss}.wav");

        _waveIn = new WaveInEvent
        {
            WaveFormat = new WaveFormat(16000, 1),
            BufferMilliseconds = 100,
        };

        _writer = new WaveFileWriter(_currentFilePath, _waveIn.WaveFormat);
        _waveIn.DataAvailable += (_, e) => _writer?.Write(e.Buffer, 0, e.BytesRecorded);
        _waveIn.RecordingStopped += (_, _) => _writer?.Flush();
        _waveIn.StartRecording();

        return Task.CompletedTask;
    }

    public Task<string> StopAsync(CancellationToken cancellationToken = default)
    {
        if (_waveIn is null || _currentFilePath is null)
        {
            throw new InvalidOperationException("Recording is not active.");
        }

        _waveIn.StopRecording();
        _waveIn.Dispose();
        _waveIn = null;

        _writer?.Dispose();
        _writer = null;

        return Task.FromResult(_currentFilePath);
    }
}
