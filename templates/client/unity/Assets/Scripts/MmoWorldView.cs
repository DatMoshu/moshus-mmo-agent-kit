#nullable enable
// Thin Unity view: one primitive per entity, WASD/arrow input. Attach to an empty GameObject.
// World units map 1:1 to Unity units on the XZ plane. Positions are interpolated toward the
// server value; the server tick is authoritative.
using System.Collections.Generic;
using UnityEngine;
using SpacetimeDB;
using SpacetimeDB.Types;

namespace MmoKit
{
    public class MmoWorldView : MonoBehaviour
    {
        [SerializeField] string serverUri = "http://127.0.0.1:3000";
        [SerializeField] string databaseName = "mmo-dev";
        [SerializeField] string playerName = "";
        [SerializeField] float smoothing = 12f;

        const string TokenKey = "mmo-kit-token";
        readonly MmoSession session = new();
        readonly Dictionary<Identity, (GameObject go, Vector3 target)> entities = new();

        void Awake() => DontDestroyOnLoad(gameObject);

        void Start()
        {
            session.Log += Debug.Log;
            session.TransformChanged += row =>
            {
                var target = new Vector3(row.X, 0f, row.Y);
                if (!entities.TryGetValue(row.Identity, out var e))
                {
                    var go = GameObject.CreatePrimitive(session.IsMe(row.Identity) ? PrimitiveType.Capsule : PrimitiveType.Cube);
                    go.name = session.IsMe(row.Identity) ? "me" : row.Identity.ToString().Substring(0, 8);
                    go.transform.position = target;
                    e = (go, target);
                }
                entities[row.Identity] = (e.go, target);
            };
            session.TransformRemoved += id =>
            {
                if (entities.Remove(id, out var e)) Destroy(e.go);
            };
            var name = string.IsNullOrWhiteSpace(playerName) ? $"unity-{Random.Range(1000, 9999)}" : playerName;
            var saved = PlayerPrefs.GetString(TokenKey, "");
            session.Connect(serverUri, databaseName, saved == "" ? null : saved,
                t => { PlayerPrefs.SetString(TokenKey, t); PlayerPrefs.Save(); }, name);
        }

        void Update()
        {
            session.Tick();
            int dx = (Input.GetKey(KeyCode.D) || Input.GetKey(KeyCode.RightArrow) ? 1 : 0) - (Input.GetKey(KeyCode.A) || Input.GetKey(KeyCode.LeftArrow) ? 1 : 0);
            int dy = (Input.GetKey(KeyCode.W) || Input.GetKey(KeyCode.UpArrow) ? 1 : 0) - (Input.GetKey(KeyCode.S) || Input.GetKey(KeyCode.DownArrow) ? 1 : 0);
            session.SetMove(dx, dy);
            float k = 1f - Mathf.Exp(-smoothing * Time.deltaTime);
            foreach (var (go, target) in entities.Values)
                go.transform.position = Vector3.Lerp(go.transform.position, target, k);
        }

        void OnDestroy() => session.Disconnect();
    }
}
