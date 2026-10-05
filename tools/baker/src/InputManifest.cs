using System.Security.Cryptography;
using System.Text.Json;

namespace MapExtract;

public static class InputManifest
{
    public static void Prepare(string outDir, string product, string build, int mapId, IEnumerable<(int, int)> targets)
    {
        Directory.CreateDirectory(outDir);
        string recipe = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(typeof(InputManifest).Assembly.Location)));
        var manifest = JsonSerializer.Serialize(new {
            schema = 1, product, build, map = mapId, recipe,
            tiles = targets.OrderBy(k => k.Item1).ThenBy(k => k.Item2)
                .Select(k => $"{mapId:0000}_{k.Item1:00}_{k.Item2:00}").ToArray()
        });
        string path = Path.Combine(outDir, "source.json");
        if (File.Exists(path))
        {
            if (File.ReadAllText(path) != manifest)
                throw new InvalidOperationException("Bake inputs changed. Use a fresh output directory to avoid mixing tiles.");
            return;
        }
        if (Directory.EnumerateFiles(outDir, "*.mmtile").Any() || Directory.Exists(Path.Combine(outDir, "status")))
            throw new InvalidOperationException("Cached tiles have no provenance. Use a fresh output directory.");
        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try { File.WriteAllText(temporary, manifest); File.Move(temporary, path); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

}
