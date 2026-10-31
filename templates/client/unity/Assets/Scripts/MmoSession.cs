#nullable enable
// Engine-agnostic session for the kit's starter world (rust-single / ts-single).
// No UnityEngine types here, so ci/SessionCheck compiles and runs this same file with plain .NET.
// Main-thread rule: call Tick() (FrameTick) and touch Conn.Db only from one thread (Unity: Update()).
using System;
using SpacetimeDB;
using SpacetimeDB.Types;

namespace MmoKit
{
    public sealed class MmoSession
    {
        public DbConnection? Conn { get; private set; }
        public Identity? Me { get; private set; }
        public bool Ready { get; private set; }
        public bool Joined { get; private set; }
        public string LastError { get; private set; } = "";

        /// <summary>Fired for every insert or update of an entity_transform row (yours and others').</summary>
        public event Action<EntityTransform>? TransformChanged;
        /// <summary>Fired when an entity leaves your subscription (logout, or out of your AOI).</summary>
        public event Action<Identity>? TransformRemoved;
        public event Action<string>? Log;

        uint seq;
        sbyte lastDx, lastDy;
        string pendingName = "";

        /// <param name="uri">e.g. http://127.0.0.1:3000</param>
        /// <param name="token">saved token for a stable identity, or null for a new one</param>
        /// <param name="saveToken">persist the token (Unity: PlayerPrefs). It is a credential; never log it.</param>
        public void Connect(string uri, string database, string? token, Action<string> saveToken, string playerName)
        {
            pendingName = playerName;
            Conn = DbConnection.Builder()
                .WithUri(uri)
                .WithDatabaseName(database)
                .WithToken(token)
                .OnConnect((conn, identity, newToken) =>
                {
                    Me = identity;
                    saveToken(newToken);
                    Log?.Invoke($"connected as {identity}");
                    // Thin starter: whole world. For a big world, subscribe to the 3x3 AOI cells
                    // around you instead (see recipes/aoi-subscriptions.md) and re-subscribe on cell change.
                    conn.SubscriptionBuilder()
                        .OnApplied(_ => { Ready = true; conn.Reducers.Join(pendingName); })
                        .OnError((_, err) => { LastError = $"subscribe: {err}"; Log?.Invoke(LastError); })
                        .Subscribe(new[]
                        {
                            "SELECT * FROM world_config",
                            "SELECT * FROM tick_health",
                            "SELECT * FROM player",
                            "SELECT * FROM entity_transform",
                        });
                })
                .OnConnectError(err => { LastError = $"connect: {err}"; Log?.Invoke(LastError); })
                .OnDisconnect((_, err) => { Ready = false; Log?.Invoke($"disconnected {err}"); })
                .Build();

            // Register row callbacks once, before the first FrameTick.
            Conn.Db.EntityTransform.OnInsert += (_, row) => TransformChanged?.Invoke(row);
            Conn.Db.EntityTransform.OnUpdate += (_, _, row) => TransformChanged?.Invoke(row);
            Conn.Db.EntityTransform.OnDelete += (_, row) => TransformRemoved?.Invoke(row.Identity);
            Conn.Reducers.OnJoin += (ctx, _) =>
            {
                if (ctx.Event.Status is Status.Committed) { Joined = true; Log?.Invoke("joined"); }
                else if (ctx.Event.Status is Status.Failed(var reason)) { LastError = $"join: {reason}"; Log?.Invoke(LastError); }
            };
        }

        /// <summary>Call every frame on the main thread.</summary>
        public void Tick() => Conn?.FrameTick();

        /// <summary>Send movement intent only when it changes. The server owns position (authoritative tick).</summary>
        public void SetMove(int dx, int dy)
        {
            if (Conn == null || !Joined) return;
            var sx = (sbyte)Math.Sign(dx);
            var sy = (sbyte)Math.Sign(dy);
            if (sx == lastDx && sy == lastDy) return;
            lastDx = sx; lastDy = sy;
            Conn.Reducers.SetInput(sx, sy, ++seq);
        }

        public bool IsMe(Identity id) => Me is Identity me && me == id;

        public void Disconnect() { Conn?.Disconnect(); Conn = null; Ready = false; Joined = false; }
    }
}
