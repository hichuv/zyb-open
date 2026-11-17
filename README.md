# 赚友吧开源版 (zyb-open)

> **版本**：`V7.0.0` (`赚友吧 V7.0 开源版`)  
> **技术栈**：Flutter 3.x / Dart 3.x / Android Native (Kotlin)  
> **开源包名**：`com.zyb.opensource`（独立包名，不与其它发行版本覆盖冲突）  
> **开源协议**：MIT License

一个使用 Flutter 构建的第三方赚客吧论坛移动客户端开源工程，包含原生论坛浏览、详情阅读、引用楼层定位、发帖回帖、评分明细、私信聊天、本地屏蔽过滤及可选的 DeepSeek AI 正文总结等功能。

**本开源仓库已彻底剥离原维护者的所有个人隐私数据、个人微信/收款二维码、个人云存储配置及第三方敏感资产，开箱即可安全二次开发或自主编译。**

---

## 📌 核心特性

- **原汁原味的现代交互**：支持浅色 / 深色双主题自适应、全局细腻触感反馈、微光防抖动加载体验；
- **高效帖子流与筛选**：支持多板块聚合、热门 / 新发布 / 新回复排序、关键词与用户黑名单屏蔽、本地阅读历史记录；
- **沉浸式原生帖子详情**：富文本 HTML 解析、引用楼层点击平滑直达并高亮、精准到秒的加果评分记录、电商链接 / 口令智能识别、高清大图浏览与保存；
- **完整社区互动能力**：多板块发帖与本地图片压缩（300KB 目标体积自动压缩）、楼层回复、评分、举报及站内私信；
- **隐私优先的 AI 辅助（可选）**：支持用户自主填入个人 DeepSeek API Token（仅通过 Android Keystore AES-GCM 加密保存在本地设备），用于长帖要点提炼；
- **零个人云依赖**：开源版默认将 `remoteConfigUrl` 置空，不连接任何第三方运营服务器；二次开发者如需自建公告/运营下发，可在 [`lib/config/constants.dart`](lib/config/constants.dart) 中填入自己的 HTTPS JSON 地址。

---

## 📁 目录结构

| 目录 / 文件 | 说明 |
| :--- | :--- |
| `lib/` | App 全部 Dart 业务源码（页面、模型、接口服务、主题与组件） |
| `android/` | Android 原生工程壳与 Kotlin 平台桥接（选图压缩、Keystore 加密、图片保存等） |
| `assets/` | 品牌静态素材（开屏图 `qd.png`） |
| `test/` | 自动化单元测试与 Widget 测试集（`test/widget_test.dart`） |
| `build_and_name.ps1` | Windows 一键自动化测试、代码混淆与 APK 构建脚本 |
| `pubspec.yaml` / `pubspec.lock` | 依赖声明与精确版本锁 |
| `接口与功能说明.md` | 架构、数据链路与二次开发说明文档 |
| `小白使用说明.md` | 环境准备、版本修改与自定义打包指南 |

---

## 🚀 快速构建与打包

### 1. 环境准备
- Flutter SDK（Dart SDK `^3.11.5`）
- Android SDK & Java 17+

### 2. 静态检查与测试
```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

### 3. 一键打包混淆版 Release APK（Windows）
在仓库根目录执行：

```powershell
# 打包单架构 arm64-v8a（主力手机包）
powershell -ExecutionPolicy Bypass -File .\build_and_name.ps1

# 或同时构建全架构瘦身包（arm64-v8a / armeabi-v7a / x86_64）
powershell -ExecutionPolicy Bypass -File .\build_and_name.ps1 -SplitPerAbi
```

构建完成后，安装包与混淆符号表将输出至 `release/zyb-open/` 目录。

> **签名提示**：仓库默认配置使用 Android `debug` 签名以方便开发者直接开箱构建测试；如需正式公开分发，请在 `android/app/build.gradle.kts` 中配置你自己的正式 `.keystore` / `.jks` 签名文件（切勿将签名密钥提交到 Git 仓库）。

---

## ⚠️ 免责声明

1. 本项目为第三方技术学习与开源研究项目，**与赚客吧官方网站及官方客户端没有任何隶属或合作关系**；
2. 请使用者遵守目标社区规范及相关法律法规，**禁止将本项目及衍生构建产物用于任何商业盈利、恶意爬取或违法违规用途**；
3. 本仓库源码不含任何开发者的个人联系方式、收款码、账号 Cookie、AI Token 或签名私钥。
