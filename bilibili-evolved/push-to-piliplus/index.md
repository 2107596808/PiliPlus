# 推送到 PiliPlus 设备

在播放器控制栏添加「推送到 PiliPlus 设备」按钮，将当前正在播放的视频（含播放进度）推送到局域网内安装了 PiliPlus（包名 `com.shaoy.piliplus`）的手机或平板。

点击按钮后会打开设备面板：可从设置中已填写的 IP 列表选择，也可以扫描局域网自动发现设备。接收端 App 会弹出确认框，确认后用同一个视频标识拉流并接着推送时刻的进度播放。

Adds a "Push to PiliPlus device" button to the video control bar, sending the current video (with playback position) to a PiliPlus app (package `com.shaoy.piliplus`) on the same LAN. The receiving app asks for confirmation, then plays the same video from the pushed position.
