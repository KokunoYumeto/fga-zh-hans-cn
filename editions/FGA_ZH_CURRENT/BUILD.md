# 中文累积版的编译

`source/zh/main.tex` 是模块式LaTeX源文件，`FGA_Chinese_Current_Direct.tex`
是包含相同内容的单文件源代码。两者均可编辑。

需要XeLaTeX、xeCJK及源文件中列出的标准LaTeX宏包，以及SimSun、
Microsoft YaHei、TeX Gyre Pagella、TeX Gyre Heros、TeX Gyre Cursor、
Latin Modern Math字体。字体不随本源代码包提供，请按各自适用的条款安装。

在 `source/zh` 目录执行 `xelatex -no-shell-escape main.tex`，重复编译，
直至目录与交叉引用稳定。单文件源代码可用同一XeLaTeX命令编译。
