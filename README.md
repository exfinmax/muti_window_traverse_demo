# muti-window-game

## 简介 | Introduction

本项目开源了 Godot 4 下多窗口穿梭、假窗口与默认窗口的主要实现逻辑，适用于学习 Godot 引擎下复杂窗口交互与自定义窗口行为。代码结构清晰，适合开发者参考和二次开发。

This repository provides the core logic for multi-window traversal, fake window, and default window implementations in Godot 4. It is intended for educational and open-source learning purposes, especially for those interested in advanced window management and custom window behaviors in Godot.

## 主要特性 | Features
- 多窗口穿梭与交互逻辑
- 假标题（自定义标题栏、拖拽、嵌入等）
- 默认窗口（无边框、嵌入锚点、拉伸、移动限制等）
- 代码注释详细，便于理解和扩展

## 使用说明 | Usage
1. 克隆本仓库到本地：
   ```bash
   git clone https://github.com/yourname/muti_window_traverse_demo.git
   ```
2. 使用 Godot 4 打开项目。
3. 阅读 `scenes/Windows/` 目录下的 `default_window.gd` 和 `fake_title.gd` 了解核心实现。

1. Clone this repository:
   ```bash
      git clone https://github.com/yourname/muti_window_traverse_demo.git

   ```
2. Open the project with Godot 4.
3. Check the core logic in `scenes/Windows/default_window.gd` and `scenes/Windows/fake_title.gd`.

## 开源协议 | License

本项目采用 [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/deed.zh) 协议，仅限非商业用途。请勿将本项目用于任何商业目的。

This project is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). Commercial use is strictly prohibited. For learning and open-source sharing only.

## 致谢 | Acknowledgements

感谢所有关注和支持本项目的开发者！欢迎 issue 和 PR 交流学习。

Thanks to all contributors and users! Issues and PRs are welcome for learning and discussion.
