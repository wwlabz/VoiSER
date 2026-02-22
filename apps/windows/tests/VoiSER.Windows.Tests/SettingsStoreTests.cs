using VoiSER.Windows.Core;
using VoiSER.Windows.Infrastructure;

namespace VoiSER.Windows.Tests;

public sealed class SettingsStoreTests
{
    [Fact]
    public async Task SavesAndLoadsSettings()
    {
        var path = Path.Combine(Path.GetTempPath(), $"voiser-settings-{Guid.NewGuid():N}.json");
        var store = new JsonSettingsStore(path);

        var input = new AppSettings
        {
            LaunchAtStartup = false,
            TextOutputMode = TextOutputMode.PasteStrict,
            ExclusiveSingleKeyEnabled = true,
            ExclusiveSingleKeyCode = 0x20,
            ExclusiveSingleKeyBlocksSystemDelivery = true,
            ModelVariant = "small",
            ComboHotkey = new HotkeyCombo(0x20, HotkeyModifiers.Control | HotkeyModifiers.Shift),
        };

        await store.SaveAsync(input);
        var loaded = await store.LoadAsync();

        Assert.False(loaded.LaunchAtStartup);
        Assert.Equal(TextOutputMode.PasteStrict, loaded.TextOutputMode);
        Assert.True(loaded.ExclusiveSingleKeyEnabled);
        Assert.Equal(0x20, loaded.ExclusiveSingleKeyCode);
        Assert.True(loaded.ExclusiveSingleKeyBlocksSystemDelivery);
        Assert.Equal("small", loaded.ModelVariant);
        Assert.Equal(0x20, loaded.ComboHotkey.KeyCode);
        Assert.Equal(HotkeyModifiers.Control | HotkeyModifiers.Shift, loaded.ComboHotkey.Modifiers);
    }
}
