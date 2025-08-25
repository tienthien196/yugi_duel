# Godot 3.6 ENet Fix Pack (Server + Client)

This pack fixes protocol mismatches between your **server_yugiDuel** and **client_yugi_duel**
projects. Drop-in replacements for autoload scripts are included.

## What’s fixed
- Server now sends **AUTH_SUCCESS** (`player_id`, `token`) right after accepting `AUTH_LOGIN`.
- Client Authentication listens to and stores token from **AUTH_SUCCESS**.
- Consistent message schema for: `LIST_ROOMS`, `ROOM_CREATED`, `JOIN_ROOM`, `GET_STATE`,
  `SUBMIT_ACTION`, `ACTION_RESULT`, `GAME_STARTED`, `GAME_STATE`, `GAME_EVENT`, `ERROR`.
- Client action helpers (`play_monster`, `activate_effect`, etc.) now call a unified
  `submit_action(action_type, payload)` that always includes `room_id` + `token` and matches the server.
- Signals on client are consistent and emitted with correct payloads.
- Server routes incoming messages through `ServerManager` and returns uniform responses.

## Files
- `client_yugi_duel/autoload/NetworkClient.gd`
- `client_yugi_duel/autoload/Authentication.gd`
- `client_yugi_duel/autoload/GameClientController.gd`
- `server_yugiDuel/autoload/NetworkManager.gd`
- `server_yugiDuel/autoload/AuthManager.gd`
- `server_yugiDuel/autoload/ServerManager.gd`

> **Note:** If your project already has richer logic (DatabaseManager, GameManager, PvEManager),
> these files interop with them via Autoload names. Keep your existing `.tscn` and other scripts.

## How to install
1. Back up your current autoload scripts.
2. Copy the files from this zip into the corresponding folders in your server/client projects.
3. Ensure the autoload singletons exist in Project Settings:
   - Client: `NetworkManager`, `Authentication`, `GameClientController`
   - Server: `NetworkManager`, `AuthManager`, `ServerManager`, `BattleCore`, `GameManager`
4. Run server project (Godot 3.6), then run client project and connect.

## Protocol (summary)
- Client → Server
  - `AUTH_LOGIN {username, password}`
  - `LIST_ROOMS {}`
  - `CREATE_ROOM {mode}`
  - `JOIN_ROOM {room_id, token}`
  - `GET_STATE {room_id, token}`
  - `SUBMIT_ACTION {room_id, token, action{type, ...}}`

- Server → Client
  - `AUTH_REQUEST {message}`
  - `AUTH_SUCCESS {player_id, token}`
  - `ROOM_LIST {rooms}`
  - `ROOM_CREATED {room_id}`
  - `GAME_STARTED {room_id}`
  - `GAME_STATE {state}`
  - `GAME_EVENT {events}`
  - `ACTION_RESULT {result}`
  - `ERROR {code, message}`
