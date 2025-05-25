

```
設備1                             設備2
| startAdvertising & Browsing        |
|----------------------------------> |
| 廣播自己, 等待邀請                    |
| <----------------------------------|
| 邀請設備2 連接                       |
|----------------------------------> |
| 交換 Discovery Token               |
| <--------------------------------- |
| UWB 會話啟動，開始測距和方向           |
```


Error creating the CFMessagePort needed to communicate with PPT.
22:31:43 >>> MCService 初始化完成，本機 PeerID: B469C
22:31:44 >>> NearbyInteractionManager 啟動
22:31:44 >>> MCService 啟動
22:31:44 >>> 開始瀏覽附近裝置: vectorchat
22:31:44 >>> 開始廣播服務: vectorchat
22:31:44 >>> NI Session 已設定並指派代理
22:31:44 >>> NI Session 準備就緒，等待 MC 連接後再發送 Discovery Token
22:31:44 >>> 發現裝置: 75552
22:31:44 >>> 本機 UUID 字典序較大或無法比較，等待對方邀請 75552
22:31:44 >>> 發現裝置: 58ECF
22:31:44 >>> 本機 UUID 字典序較大或無法比較，等待對方邀請 58ECF
22:31:44 >>> 發現裝置: 58ECF
22:31:44 >>> 本機 UUID 字典序較大或無法比較，等待對方邀請 58ECF
22:31:44 >>> 發現裝置: 58ECF
22:31:44 >>> 本機 UUID 字典序較大或無法比較，等待對方邀請 58ECF
22:31:46 >>> 發現裝置: 58ECF
22:31:46 >>> 本機 UUID 字典序較大或無法比較，等待對方邀請 58ECF
22:31:49 >>> 收到來自 58ECF 的連接邀請
22:31:49 >>> 為 58ECF 創建獨立 MCSession
22:31:49 >>> 已接受來自 58ECF 的連接邀請，使用獨立 Session
22:31:49 >>> 重置連接嘗試計數器給 58ECF
22:31:49 >>> 獨立 Session 與 58ECF 正在連接...
22:31:49 >>> 獨立 Session 與 58ECF 已連接
22:31:49 >>> 重置連接嘗試計數器給 58ECF
22:31:49 >>> 目前已連接的裝置數: 1
22:31:51 >>> 確認 58ECF 連接穩定，觸發回調
22:31:52 >>> 觸發 Discovery Token 發送
22:31:52 >>> 成功傳送 Discovery Token 給 58ECF
22:31:52 >>> 已傳送 Discovery Token 給 1 個新連接的 peers
22:31:52 >>> 從 58ECF 收到資料，長度: 311
22:31:52 >>> 成功從 58ECF 收到 Discovery Token
22:31:53 >>> 將 58ECF 的配置請求加入隊列，隊列長度: 1
22:31:53 >>> 開始處理配置隊列，為 58ECF 配置 NI
22:31:53 >>> 為 58ECF 成功運行 NI Configuration
Not in connected state, so giving up for participant [35B222E7] on channel [0].
Not in connected state, so giving up for participant [35B222E7] on channel [1].
Not in connected state, so giving up for participant [35B222E7] on channel [2].
Not in connected state, so giving up for participant [35B222E7] on channel [3].
22:32:08 >>> 收到來自 75552 的連接邀請
22:32:08 >>> 為 75552 創建獨立 MCSession
22:32:08 >>> 已接受來自 75552 的連接邀請，使用獨立 Session
22:32:08 >>> 重置連接嘗試計數器給 75552
22:32:08 >>> 獨立 Session 與 75552 正在連接...
22:32:08 >>> 獨立 Session 與 75552 已連接
22:32:08 >>> 重置連接嘗試計數器給 75552
22:32:08 >>> 目前已連接的裝置數: 2
22:32:08 >>> 發現裝置: 75552
22:32:08 >>> 裝置 75552 已連接或正在連接，忽略此次發現
22:32:10 >>> 確認 75552 連接穩定，觸發回調
22:32:11 >>> Discovery Token 已發送過，跳過重複發送
22:32:11 >>> 從 75552 收到資料，長度: 311
22:32:11 >>> 成功從 75552 收到 Discovery Token
22:32:12 >>> 將 75552 的配置請求加入隊列，隊列長度: 1
22:32:12 >>> 開始處理配置隊列，為 75552 配置 NI
22:32:12 >>> 為 75552 成功運行 NI Configuration
Not in connected state, so giving up for participant [01EEBF38] on channel [0].
Not in connected state, so giving up for participant [01EEBF38] on channel [1].
Not in connected state, so giving up for participant [01EEBF38] on channel [2].
Not in connected state, so giving up for participant [01EEBF38] on channel [3].