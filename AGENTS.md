# 仓库指南

PiliPlus 是一个使用 Flutter 开发的跨平台 Bilibili 客户端，支持 Android、iOS、Windows、Linux 和 macOS。状态管理使用 GetX，网络层使用 dio 与 gRPC。

## 项目结构与模块组织

Dart 源码位于 `lib/`：

- `pages/` — 界面；`common/` — 通用组件与常量；`router/` — GetX 路由定义。
- `http/`、`grpc/`、`tcp/` — 网络层；`services/` — 全局服务（账号、下载）；`models/` 与 `models_new/` — 数据模型；`plugin/` — 功能模块（播放器）；`utils/` — 工具函数与扩展。
- `assets/` — 图片、字体、着色器与截图。
- `android/`、`ios/`、`windows/`、`linux/`、`macos/` — 平台代码与打包配置；`tool/` — 代码生成；`lib/scripts/` — CI 补丁与构建脚本。
- `browser-extension/` — 独立 MV3 浏览器扩展（电脑端推送到手机）；`bilibili-evolved/` — Bilibili-Evolved 组件源码与编译产物，两者复用同一套 Cast HTTP 协议（`lib/services/cast/`，端口 26982）。
- 目前没有 `test/` 目录，新增测试时放在 `test/` 下。

## 构建、测试与开发命令

Flutter 版本通过 FVM 固定为 3.44.8（`.fvmrc`），请使用 `fvm`：

- `fvm flutter pub get` — 安装依赖（部分为 Git fork，改动依赖时同步更新 `pubspec.lock`）。
- `fvm flutter run -d windows|linux|macos|<设备>` — 本地运行。
- `fvm flutter analyze` — 静态分析，合并前必须通过。
- `fvm flutter test` — 运行测试。
- `fvm dart run build_runner build --delete-conflicting-outputs` — 重新生成 JSON 序列化代码。
- `fvm dart run tool/jnigen.dart` — 重新生成 JNI 绑定。
- 发布构建：`pub get` 后先运行 `lib/scripts/patch.ps1 <平台>` 应用 Flutter SDK 补丁（平台行为依赖这些补丁），再执行 `fvm flutter build <apk|windows|...> --release`。

## 发布流程

本仓库发布到 `2107596808/PiliPlus`，更新检查也指向该仓库。本地发布步骤：

1. 版本号：`versionName` 与 pubspec 一致（当前 2.1.0），`versionCode` 取 `git rev-list --count HEAD`（当前 5168）。
2. 打 Android v8a 包时必须传 `pili.*` dart-define（`pili.time` 为当前 Unix 秒，`pili.hash` 为 `git rev-parse HEAD`）；否则 `BuildConfig.buildTime` 为 0，安装后每次启动都会误报更新：

```powershell
flutter build apk --release --split-per-abi --target-platform android-arm64 `
  --build-name <versionName> --build-number <versionCode> `
  --dart-define=pili.code=<versionCode> --dart-define=pili.name=<versionName> `
  --dart-define=pili.hash=<commitHash> --dart-define=pili.time=<unixSeconds>
```

3. 发布到 GitHub：

```bash
git tag v<versionName> && git push origin v<versionName>
gh release create v<versionName> build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --title "PiliPlus v<versionName>" --notes-file <notes.md>
# 覆盖已有附件：gh release upload v<versionName> <apk> --clobber
```

注意事项：仅发布 arm64-v8a 包；无 `android/key.properties` 时使用 debug 签名，正式分发前需配置；旧包名（`com.example.piliplus`）应用升级前需先卸载；更新检查用 release 的创建时间与 `pili.time` 比较，因此时间戳必须新鲜。

## 编码风格与命名规范

- 遵循 `analysis_options.yaml`：`flutter_lints` 外加严格规则（`avoid_print`、`prefer_const_constructors`、`always_declare_return_types`、强制 package 导入）。
- 使用 `dart format` 格式化；VS Code 已开启保存时格式化与整理 import。
- 命名：文件 `snake_case.dart`、变量/函数 `camelCase`、类 `UpperCamelCase`、常量 `SCREAMING_SNAKE_CASE`。
- 使用 package 导入（`package:PiliPlus/...`），避免跨模块相对导入。

## 测试规范

- 框架：`flutter_test`。测试放在 `test/`，文件名以 `_test.dart` 结尾（如 `test/models/xx_test.dart`）。
- 目前仓库还没有提交测试，新增逻辑时尽量一并补充。

## 提交与 Pull Request 规范

- 提交信息沿用历史中的短前缀：`feat:`、`fix:`、`opt:`（优化）、`refactor:`、`perf:`、`upgrade deps`、`flutter <版本>`（工具链升级），可加作用域（如 `fix(macos): ... (#2448)`）。
- 摘要控制在 72 字符以内，并引用相关 issue/PR 编号。
- PR 需说明改了什么及原因、关联 issue，界面改动附截图。CI 会对每个 PR 构建所有平台（仅文档改动除外）。

## 给 Agent 的注意事项

- 不要修改生成代码：`lib/grpc/bilibili/`、`*.g.dart` 与平台构建产物已被排除在分析之外。
- 改动保持在模块边界内：界面放 `pages/`、通用组件放 `common/widgets/`、网络代码放 `http/` 或 `grpc/`。
