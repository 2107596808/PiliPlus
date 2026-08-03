# 推送到 PiliPlus（Bilibili-Evolved 组件）

为 [Bilibili-Evolved](https://github.com/the1812/Bilibili-Evolved) 编写的组件：在 B 站播放器控制栏新增「推送到 PiliPlus」按钮，把当前播放的视频（含进度）推送到局域网内安装了 PiliPlus（包名 `com.shaoy.piliplus`）的设备。

与独立浏览器扩展的关系：两者的推送协议完全一致，App 端只需一个带 HTTP 接口的版本（`GET /ping`、`POST /push`，端口 26982）。二选一即可，也可并存。

## 安装

1. 安装 Bilibili-Evolved（需 Tampermonkey 等油猴管理器）。
2. 打开脚本设置面板 → 组件管理，粘贴以下链接安装：

```
https://raw.githubusercontent.com/2107596808/PiliPlus/main/bilibili-evolved/dist/push-to-piliplus.js
```

3. 打开任意 B 站视频播放页，在播放器控制栏点击「推送到 PiliPlus」按钮。
4. 在组件设置中建议填写：
   - 设备 IP（每行一个），或
   - 局域网网段（如 `192.168.1`），面板内点击「扫描」自动发现设备。

接收端 App 需与电脑在同一网络，且设置中「接收设备推送」保持开启；收到推送后 App 会弹窗确认，确认后接着当前进度播放。

## 开发

源码位于 `push-to-piliplus/`（`index.ts` + `index.md` + `style.scss`），构建方式见官方 [CONTRIBUTING.md](https://github.com/the1812/Bilibili-Evolved/blob/master/CONTRIBUTING.md)：

```powershell
git clone https://github.com/the1812/Bilibili-Evolved.git
cd Bilibili-Evolved
pnpm install
cd registry
pnpm install
cd ..
# 把 push-to-piliplus 复制到 registry/lib/components/video/ 下
pnpm tsx dev-tools/dev-server/index.ts   # 启动开发服务（端口 23333）
pnpm tsx dev-tools/dev-server/command.ts build component video/push-to-piliplus production
# 产物：registry/dist/components/video/push-to-piliplus.js
```

把产物复制回本目录 `dist/push-to-piliplus.js` 并提交，即可更新安装链接对应的文件。

## 协议

复用 App 内置的 Cast 协议 v1（`lib/services/cast/cast_models.dart`）：

- `GET http://<ip>:26982/ping` → `{ok, name, app, v, receiving}`
- `POST http://<ip>:26982/push`，body 为 `{t:'push', id, v:1, app:'com.shaoy.piliplus', from, payload:{type, bvid, aid, cid, epId, seasonId, title, cover, positionSec}}` → `{t:'ack', ...}`
