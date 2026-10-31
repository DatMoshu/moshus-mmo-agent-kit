// Deliberately wrong C# code.
[SpacetimeDB.Table(Name = "Player", Public = true)]
public partial struct Player { }
[SpacetimeDB.Reducer(ReducerKind.Connect)]
public static void OnConnect(ReducerContext ctx) { }
