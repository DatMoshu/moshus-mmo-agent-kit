// dotnet run -- http://127.0.0.1:3000 mmo-dev   -> exit 0 = SESSION PASS
using System;
using System.Collections.Generic;
using System.Threading;
using SpacetimeDB;
using SpacetimeDB.Types;
using MmoKit;

var uri = args.Length > 0 ? args[0] : "http://127.0.0.1:3000";
var db = args.Length > 1 ? args[1] : "mmo-dev";
var a = new MmoSession();
var b = new MmoSession();
var seenByA = new Dictionary<Identity, EntityTransform>();
var seenByB = new Dictionary<Identity, EntityTransform>();
a.TransformChanged += r => seenByA[r.Identity] = r;
b.TransformChanged += r => seenByB[r.Identity] = r;
var rnd = new Random().Next(10000, 99999);
a.Connect(uri, db, null, _ => { }, $"cs-a-{rnd}");
b.Connect(uri, db, null, _ => { }, $"cs-b-{rnd}");

var deadline = DateTime.UtcNow.AddSeconds(30);
(float x, float y)? bStart = null, aStart = null;
bool moved = false;
while (DateTime.UtcNow < deadline)
{
    a.Tick(); b.Tick();
    if (a.Joined && b.Joined && a.Me is Identity ia && b.Me is Identity ib
        && seenByA.TryGetValue(ib, out var bInA) && seenByB.TryGetValue(ia, out var aInB))
    {
        if (!moved) { aStart = (aInB.X, aInB.Y); bStart = (bInA.X, bInA.Y); a.SetMove(1, 0); b.SetMove(0, 1); moved = true; }
        else if (aInB.X > aStart!.Value.x + 1 && bInA.Y > bStart!.Value.y + 1)
        {
            a.SetMove(0, 0); b.SetMove(0, 0);
            for (int i = 0; i < 10; i++) { a.Tick(); b.Tick(); Thread.Sleep(20); }
            Console.WriteLine($"A sees B at ({bInA.X:F1},{bInA.Y:F1}); B sees A at ({aInB.X:F1},{aInB.Y:F1})");
            Console.WriteLine("SESSION PASS");
            a.Disconnect(); b.Disconnect();
            return 0;
        }
    }
    Thread.Sleep(16);
}
Console.WriteLine($"SESSION FAIL a.joined={a.Joined} b.joined={b.Joined} a.err={a.LastError} b.err={b.LastError} seenA={seenByA.Count} seenB={seenByB.Count}");
return 1;
