# Translations

The addon ships in deDE, esES, esMX, frFR, koKR, ptBR, ruRU, zhCN and zhTW, every language the WoW: Forever
client offers besides English (it has no itIT). Those files are machine translated, and each says so at its top. In
`frFR.lua`, a line ending `-- mt` is machine translated and the rest are Brainc3ll's.

To correct a line, change its right-hand side and drop its `-- mt`; a corrected line is never overwritten by a
machine one. To translate a new language or fill a gap, copy `phrases.txt` to `<locale>.lua` (say `deDE.lua`), set
that code at the top, translate the right-hand side of each line and delete the lines you leave in English. List a
new file in `ShortestPathForever.toc` straight after `Locales\enUS.lua` and open a pull request. If that's a
hassle, paste your lines into a [translation issue](https://github.com/cjber/shortest-path-forever/issues/new?template=translation.yml)
and I'll add them.

`python3 tools/check_locales.py` checks every file against `phrases.txt` and prints each language's coverage. A
phrase a file leaves out stays in English.
