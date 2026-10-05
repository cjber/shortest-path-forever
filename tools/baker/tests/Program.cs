using MapExtract;

string root = Path.Combine(Path.GetTempPath(), "spf-provenance-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try
{
    var tiles = new[] { (30, 31), (30, 30) };
    InputManifest.Prepare(root, "wow_classic_beta", "1.60.1.69913", 0, tiles);
    string original = File.ReadAllText(Path.Combine(root, "source.json"));
    InputManifest.Prepare(root, "wow_classic_beta", "1.60.1.69913", 0, tiles.Reverse());
    ExpectFailure(() => InputManifest.Prepare(root, "wow_classic_beta", "1.60.1.70000", 0, tiles));
    ExpectFailure(() => InputManifest.Prepare(root, "wow_classic_beta", "1.60.1.69913", 0, tiles.Take(1)));
    if (File.ReadAllText(Path.Combine(root, "source.json")) != original) throw new Exception("Rejected inputs modified provenance");
    string stale = Path.Combine(root, "stale");
    Directory.CreateDirectory(Path.Combine(stale, "status"));
    ExpectFailure(() => InputManifest.Prepare(stale, "wow_classic_beta", "1.60.1.69913", 0, tiles));
    Console.WriteLine("Bake provenance: deterministic inventory, changed build and unproven cache pass");
}
finally
{
    foreach (string file in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)) File.Delete(file);
    Directory.Delete(Path.Combine(root, "stale", "status"));
    Directory.Delete(Path.Combine(root, "stale"));
    Directory.Delete(root);
}

static void ExpectFailure(Action action)
{
    try { action(); }
    catch (InvalidOperationException) { return; }
    throw new Exception("Unsafe resume accepted");
}
