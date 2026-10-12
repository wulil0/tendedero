<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/zh-Hans/hero-dark.png">
  <img src="../images/zh-Hans/hero-light.png" alt="Tendedero。截图挂起来晾着。三张截图装在玻璃相框里，挂在 macOS 菜单栏下方的一根细绳上。">
</picture>

<h3 align="center"><a href="https://tendedero.app/?lang=zh-Hans">在 tendedero.app 上直接用浏览器试用&nbsp;&rsaquo;</a></h3>

<p align="center">
  免费开源。适用于 macOS 14 及以上。
  <br>
  <a href="../../../../releases/latest">下载&nbsp;&rsaquo;</a>
  &nbsp;&nbsp;
  <a href="#从源码构建">从源码构建&nbsp;&rsaquo;</a>
  <br><br>
  <a href="../../README.md">English</a>&nbsp;·&nbsp;<a href="README.es.md">Español</a>&nbsp;·&nbsp;<a href="README.gl.md">Galego</a>&nbsp;·&nbsp;<a href="README.fr.md">Français</a>&nbsp;·&nbsp;<a href="README.pt-BR.md">Português (Brasil)</a>&nbsp;·&nbsp;<a href="README.ja.md">日本語</a>&nbsp;·&nbsp;<a href="README.ko.md">한국어</a>&nbsp;·&nbsp;简体中文&nbsp;·&nbsp;<a href="README.tr.md">Türkçe</a>&nbsp;·&nbsp;<a href="README.az.md">Azərbaycanca</a>
  <br>
  <sub>本文译自英文 README。如有出入，以英文版为准。</sub>
</p>

<p align="center">
  <a href="https://trendshift.io/repositories/287033?utm_source=trendshift-badge&amp;utm_medium=badge&amp;utm_campaign=badge-trendshift-287033" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/287033/daily?language=Swift" alt="alejandrobujan%2Ftendedero | Trendshift" width="250" height="55"/></a>
</p>

<br>

## 看不见，却够得着

你每截一张图，它都会挂到屏幕顶上的一根绳上。
把指针停在菜单栏，绳子就滑下来；移开，它就收起。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/zh-Hans/demo-dark.gif">
  <img src="../images/zh-Hans/demo-light.gif" alt="指针停在上边缘，绳子带着三张截图轻轻摇晃着滑下来，单击复制其中一张，指针离开后绳子收起。">
</picture>

<br>
<br>

## 每个动作都有手势

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../images/zh-Hans/bento-dark.png">
  <img src="../images/zh-Hans/bento-light.png" alt="单击复制。长按标记。拖拽分享。松手放下。">
</picture>

<br>
<br>

| | |
|:--|:--|
| 单击 | 复制它。 |
| 指针停在上面 | 在绳子下方看大图。 |
| 长按 | 用「标记」打开。文字用编辑器打开，文件用「快速查看」打开。 |
| 双击 | 用「预览」打开。 |
| 用力点按 | 用「快速查看」看一眼。 |
| 右键点按 | 固定、重新挂上绳、在访达中显示等。 |
| 拖进 App | 送一份副本过去。原图仍挂在绳上。文字拖过去就是文字。 |
| 拖进文件夹 | 存在那儿。原图从绳上取下。 |
| 拖到废纸篓，或点叉 | 松手丢弃。 |
| 指针停在菜单栏 | 在那一块屏幕上放下绳子。 |
| 点击菜单栏任意处 | 把绳子收起来。 |
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>T</kbd> | 显示或隐藏绳子。可在菜单栏的「快捷键」中更改。 |

<br>

## 桌面，终于清爽了

把截图交给 Tendedero<sup>1</sup>，它们就完全跳过桌面。
没有浮动缩略图。不用等五秒。拍下的瞬间即挂上绳，只有你拖出去的才会留下。

屏幕录制也会挂上绳，上面带一个播放按钮。按住即可剪辑。

同样的快捷键。同样的肌肉记忆。只是少了乱。

<br>

## 复制什么，挂什么

图片、文字、文件在菜单栏里各有一个开关：「挂上复制的图片」「挂上复制的文本」
「挂上复制的文件」。任一开关打开时，图标里的衬衫会被填满。密码管理器标为私密的
内容不会被挂上。

- **图片。** 按住 <kbd>⌃</kbd> 截图，或在「预览」中复制图片，它就会像其他截图一样挂上绳。
- **文字。** 挂成一张便条。从 Word、Pages 或网页复制时会保留格式，粘贴时格式也在。
- **链接**把网站名放大显示。`#FF8800` 这样的**色码**会让整张卡片变成那个颜色。**代码**用等宽字体显示，保留缩进。
- **文件**在访达中复制后原地挂上，显示图标或预览。从绳上取下不会删除它。

每一类都用自己的夹子：图片是铝，屏幕录制是玫瑰红，文字是桦木，链接是蓝色，
代码是石墨，文件是黄铜，色码则是那个颜色本身。

同一样东西复制两次，它的卡片会移到最新的位置，而不是再挂一张。

<br>

## 历史记录，而不是悬崖

最新的卡片挂在最左边，越往右越旧。绳子挂满后，最旧的卡片不再掉下去，而是进入
历史记录，叠放在绳子的最右端。指针停在这一叠上或点一下，历史记录就会沿着绳子
展开，最新的在前，一次显示六张，其余的左右滑动即可看到。滑到两端时绳子会被拉开一点，松手后弹回。绳子收起时，
历史记录会重新叠好。

取下一张卡片，历史记录里最新的那张就会回来补上空位。固定的卡片永远不会被
挤进历史记录。历史记录最多保留 100 张，也可以在菜单栏里查看。

**搜索。** 展开的历史记录下方挂着一个搜索签。输入文字后，只有符合的卡片
留在绳上，绳上和历史记录里的都会一起搜。搜索范围包括名称、复制的文字、PDF、
文档和纯文本文件、文件夹里的文件名，以及图片中的文字——由你的 Mac 自带的
文字识别读出。

<br>

## 键盘也行

用快捷键打开绳子时，它会接管键盘。用其他方式打开时，你正在输入的内容不受影响。

| | |
|:--|:--|
| <kbd>←</kbd>&thinsp;<kbd>→</kbd> | 选择卡片。 |
| <kbd>Return</kbd> | 复制。 |
| <kbd>空格</kbd> | 用「快速查看」看一眼。 |
| <kbd>⌘</kbd>&thinsp;<kbd>1</kbd> 至 <kbd>⌘</kbd>&thinsp;<kbd>9</kbd> | 复制最新的几张。 |
| <kbd>Esc</kbd> | 收起绳子。 |

<br>

## 浅色与深色

绳子会跟随你的 Mac 切换到深色模式，再切回来。便条、链接、代码和文件卡片会变成
深色纸、浅色字，截图则蒙上一层柔和的暗色，明亮的截图不会刺眼。指针停在上面，
就能看到原本的亮度。想让绳子不随系统、始终保持浅色或深色，可在菜单栏的「外观」中选择。

<br>

## 隐私是设计前提

没有账号。不联网。无统计。
Tendedero 完全在你的 Mac 上运行，你截下或复制的任何内容都不会离开这台电脑。
链接只显示、不打开。图片中的文字在本机识别，搜索读到的内容只保存在
Tendedero 自己的文件夹里，只有你能读取。

<br>

## 技术规格

| | |
|:--|:--|
| **兼容性** | macOS 14 Sonoma 及以上，Apple 芯片与 Intel 均支持。已针对 macOS 27 设计。 |
| **体积** | 4.2 MB |
| **语言** | 英语、西班牙语、加利西亚语、法语、巴西葡萄牙语、日语、韩语、简体中文、土耳其语、阿塞拜疆语 |
| **技术栈** | Swift、AppKit 与 SwiftUI |
| **网络访问** | 无 |
| **价格** | 免费 |
| **许可** | 代码为 MIT。名称与图标不在授权范围内。 |

<br>

## 安装

从[最新发布](../../../../releases/latest)下载磁盘映像，打开后把 Tendedero 拖进「应用程序」。也可以用 Homebrew 安装：

```sh
brew install --cask alejandrobujan/tap/tendedero
```

Tendedero 已使用 Developer ID 签名并通过 Apple 公证，打开方式和其他 App 一样。

<br>

## 从源码构建

```sh
git clone git@github.com:alejandrobujan/tendedero.git
cd tendedero
scripts/build-app.sh
open build/Tendedero.app
```

也可以一步完成构建，并安装到「应用程序」替换原有版本：

```sh
scripts/install.sh
```

需要 Swift 工具链，Xcode 可选。若使用 macOS 27 的命令行工具，脚本会回退到随其一同安装的 macOS 26 SDK，因为新版 SDK 需要只有 Xcode 才带的 SwiftUI 宏插件。本地构建采用 ad-hoc 签名，所以每次重新构建后 macOS 都会再次询问桌面访问权限。若想保留权限，可在「钥匙串访问」中用「证书助理 → 创建证书」创建一个名为 `Tendedero Local`、类型为「代码签名」的自签名证书，脚本找到它时就会用它签名。

<details>
<summary>应用内部</summary>
<br>

| 文件 | 作用 |
|:--|:--|
| `AppDelegate.swift` | 菜单栏、快捷键、放下与收起绳子 |
| `LinePanel.swift` | 屏幕顶部那条透明的窄条 |
| `LineView.swift` | 绳子本身，以及每张照片挂在哪里 |
| `PeggedView.swift` | 一张照片：玻璃相框、夹子、摇摆与微风 |
| `GrabArea.swift` | 单击、长按、拖放 |
| `Cards.swift` | 把文字、链接、色码、代码和文件画成卡片 |
| `History.swift` | 历史记录的叠放、搜索签和菜单 |
| `HoverPreview.swift` | 在绳子下方显示卡片的大图 |
| `SearchIndex.swift` | 读出图片和文件中的文字，供搜索使用 |
| `ScreenshotWatcher.swift` | 发现新的截图 |
| `Inbox.swift` | 接管截图设置，之后再把它们放回去 |
| `ClipboardWatcher.swift` | 发现复制到剪贴板的图片、文字和文件 |
| `Markup.swift` | 打开系统「标记」编辑器并保存结果 |
| `Trim.swift` | 剪辑屏幕录制并保存结果 |
| `FullScreen.swift` | 判断何时该保持隐藏 |
| `Line.swift` | 绳上挂着什么，以及你能对它做什么 |

这里出现的每一张图——包括图标——都是由代码绘制的：
`scripts/make-icon.swift` 与 `scripts/make-readme-art.swift`。
`scripts/make-dmg.sh` 负责构建发布用的磁盘映像。

翻译文件位于 `Sources/Tendedero/Resources`，每种语言一个 `.lproj` 文件夹。
`swift scripts/check-strings.swift` 会检查是否有遗漏。

</details>

<br>

---

<sub>
1. 首次启动时，Tendedero 会询问是否接管你的截图。如果同意，它会关闭浮动缩略图，并把新截图保存到它自己的文件夹，这两项设置也可以在 Cmd+Shift+5 的「选项」中找到。你原来的设置会被保存，并在退出 Tendedero 或从菜单栏关闭该选项时恢复。当有 App 处于全屏时，Tendedero 会自动隐藏。
</sub>

<br>
<br>

<p align="center">
  <img src="../images/icon.png" width="64" height="64" alt="">
  <br>
  <sub>代码采用 MIT 许可。Tendedero 这一名称与图标不在许可范围内，因此 fork 需要自备名称与图标。详见 <a href="../../LICENSE">LICENSE</a>。</sub>
  <br>
  <sub>由 <a href="https://alejandrobujan.com">Alejandro Buján</a> 设计与开发。</sub>
</p>
