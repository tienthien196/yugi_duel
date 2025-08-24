
```
+----------------+          +---------------------+
|                |  HTTP    |                     |
|   Client A     |<-------->|   Authentication    |
| (Người chơi 1) |          |     & REST API      |
|                |          | (Login, Deck, Shop) |
+-------+--------+          +----------+----------+
        |                            |
        | WebSocket                  | Database
        | (Real-time Duel)           | (PostgreSQL/MongoDB)
        v                            |
+----------------+          +--------+----------+
|                |          |                   |
|   Client B     |<-------->|    Matchmaking    |
| (Người chơi 2) |          |     Service       |
|                |          | (Tìm phòng, tạo ID)|
+----------------+          +-------------------+
                                      |
                                      v
                          +---------------------------+
                          |                           |
                          |        GAME SERVER        |
                          | (Xử lý lượt đi, hiệu ứng) |
                          |                           |
                          +---------------------------+
                                      |
              +-----------------------------------------------+
              |                   WebSocket                   |
              +-----------------------------------------------+
              |                                               |
              v                                               v
+-----------------------------+               +-----------------------------+
|         GAME ROOM           |<------------->|         GAME ROOM           |
|       (Trạng thái trận)     |   Sync State  |       (Dữ liệu đồng bộ)       |
|-----------------------------|               |-----------------------------|
| - room_id: duel_789         |               | - players: [user_123, ...]  |
| - turn: user_123            |               | - phase: main1               |
| - phase: battle             |               | - self: {hand, lp, ...}      |
| - chain: [...]              |               | - opponent: {hand_count, ...}|
| - players: [...]            |               | - events: [...]              |
+-----------------------------+               +-----------------------------+

              ▲                                               ▲
              | Action (JSON)                               | Event (JSON)
              |                                               |
     +--------+--------+                          +---------+---------+
     |                 |                          |                   |
     |   ACTION        |                          |   EVENT           |
     |-----------------|                          |-------------------|
     | type: PLAY_CARD |                          | event: CARD_DRAWN |
     | payload: {      |                          | data: {card_id}   |
     |   card_id: "C1" |                          |                   |
     |   from: "hand"  |                          | event: DAMAGE     |
     | }               |                          | data: {amount:500}|
     +-----------------+                          +-------------------+

              ▲                                               ▼
              |                                               |
     +--------+--------+                          +----------+----------+
     |                 |                          |                     |
     |   CLIENT A/B    |<-------------------------+      SERVER         |
     |  (Gửi hành động) |     Gửi trạng thái mới  | (Xử lý logic bài)   |
     |                 |                          | - Kiểm tra điều kiện|
     +-----------------+                          | - Xử lý chain       |
                                                  | - Tính damage       |
                                                  | - Đồng bộ bàn chơi  |
                                                  +---------------------+
```