# Translations

The addon ships in deDE, esES, esMX, frFR, koKR, ptBR, ruRU, zhCN and zhTW, every language the WoW: Forever
client offers besides English (it has no itIT). Those files are machine translated, and each says so at its top. In
`frFR.lua`, a line ending `-- mt` is machine translated and the rest are Brainc3ll's.

To correct a line, change its right-hand side in that language's file. A corrected line is never overwritten by
a machine one: in `frFR.lua` drop its `-- mt`; in a file that is all machine translated, end every other line with
`-- mt` and change the top comment to say so, as `frFR.lua` does (or leave that to me). To fill a gap, add the
missing line from `phrases.txt` to the existing file. A new language starts as a copy of `phrases.txt` named
`<locale>.lua`: set that code at the top, translate the right-hand side of each line, delete the lines you leave in
English and list the file in `ShortestPathForever.toc` straight after the other `Locales` files. Then open a pull
request. If that's a
hassle, paste your lines into a [translation issue](https://github.com/cjber/shortest-path-forever/issues/new?template=translation.yml)
and I'll add them.

`python3 tools/check_locales.py` checks every file against `phrases.txt` and prints each language's coverage. A
phrase a file leaves out stays in English.
