# 《代数几何基础》简体中文版

本包是 Alexandre Grothendieck 的 *Fondements de la géométrie algébrique*
（FGA）的独立、非官方中国大陆简体中文版本。译文完整覆盖第 149、182、190、
195、212、221、232、236 次布尔巴基讨论班报告、1962 年《评注》，以及八份相关
勘误，截止第 236 次报告勘误的末尾。

主阅读文件为 `fga-zh-hans-cn.pdf`。可编辑源文件和精简证据归档为
`fga-zh-hans-cn-source.zip`；解压后在 `01_source/zh` 目录中重复运行 XeLaTeX，
直至连续两遍输出不再变化。一次全新目录回放在第 3 遍生成稳定内容，并由第 4、5 遍
确认收敛：

```text
xelatex -interaction=nonstopmode -halt-on-error -file-line-error main.tex
```

译文保留公式、编号、标签、交叉引用、图式、引文、原页锚点和稳定单元标识。
发布字节经来源回放、结构与公式检查、确定性构建收敛、字体和字形检查、文本提取、
内部链接验证、归档成员验证、隐私扫描和有界视觉检查。当前状态为“生产者完成并通过
机械与视觉 QA”，不冒充独立中文审校认证。

NUMDAM 权威扫描、法文文本和英文对照文件均不在本包内；仅在 `PROVENANCE.json`
和 `provenance/AUTHORITY.csv` 中记录其公开标识与哈希。既有多语言记录
`10.5281/zenodo.22083916` 作为历史来源保留，但不是此语言专属概念谱系的前一版本。

本包不冒充原作者、布尔巴基讨论班、NUMDAM、出版者或任何机构的官方版本，也不对
FGA 原文作新的开放许可或公共领域声明。详见 `RIGHTS.md`。
