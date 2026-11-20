// node tools/test.js → runs addon/ForeverCleanse/Core.lua on the fake WoW in tools/test.lua (fengari, Lua 5.3)
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require(path.join(process.env.LOCALAPPDATA, 'fp-lua/node_modules/fengari'));
const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
lua.lua_getglobal(L, to_luastring('print')); lua.lua_setglobal(L, to_luastring('print_real'));
if (lauxlib.luaL_loadfile(L, to_luastring(path.join(__dirname, 'test.lua'))) !== 0) throw new Error(lua.lua_tojsstring(L, -1));
lua.lua_pushstring(L, to_luastring(path.join(__dirname, '../addon/ForeverCleanse/Core.lua')));
if (lua.lua_pcall(L, 1, 0, 0) !== 0) { console.error('FALLITA: ' + lua.lua_tojsstring(L, -1)); process.exit(1); }
