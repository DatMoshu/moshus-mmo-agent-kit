# Following your player across regions (sharded client)

The `rust-sharded` template splits the world into one **global** database (login, region directory, home region)
and N **region** databases (simulation). When a player crosses a border, the region modules hand them off
over IDC (`lock → offer → accept → delete → activate`). The client must follow.

Working example: [`templates/server/rust-sharded/client-example/src/hop.ts`](../templates/server/rust-sharded/client-example/src/hop.ts)

1. Connect to **global**. Read the `region` table (`id → database_name`) and `my_home`.
2. Connect to the home region **with the same token**. Your identity is the same in every database on the host, so the
   region knows you. Call `join` and subscribe to `my_player`, `my_departure` and your AOI cells.
3. Move. When a row appears in `my_departure`, the server has already locked you and sent you onward.
   Disconnect, then connect to `regions.get(to_region)` with the same token.
4. Wait until `my_player.state === 0` (active) before sending input. Inputs sent during the hop are dropped on purpose.

```bash
cd templates/server/rust-sharded/client-example && npm install
npx tsx src/hop.ts --uri ws://127.0.0.1:3000 --global my-mmo-global --hops 2
```

**Checked (2026-10-31, local 2.14):** Ran against one global and three region databases with `--hops 2`.
Output was `HOP PASS`: two real cross-database handoffs, and the identity stayed the same throughout.

**For real clients:** keep the old region's connection open until the new one confirms `state === 0`, so the screen
never goes blank. Show a short "crossing" effect. Players near a border should also subscribe to the neighbour
region's edge cells (read-only), which is optional polish.
