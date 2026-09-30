-- Sample of WTF/Account/<name>/SavedVariables/WeakAuras.lua for build_spec (import-snapshots).
-- WeakAuras 5.22 keeps aura_env.saved as a string in information.saved:
-- LibSerialize:SerializeEx -> LibDeflate:CompressDeflate (level 1) -> LibDeflate:EncodeForPrint
-- (Private.SaveAuraEnvironment in WeakAuras/AuraEnvironment.lua). The string below holds
-- { swing = { reset = { stormstrike = true } }, enhrotSnapshots = { two snapshots } }.

WeakAurasSaved = {
	["dynamicIconCache"] = {
	},
	["displays"] = {
		["EnhRot"] = {
			["id"] = "EnhRot",
			["regionType"] = "group",
		},
		["EnhRot Timeline"] = {
			["id"] = "EnhRot Timeline",
			["information"] = {
				["saved"] = "Jr1(uQ5Lrr5xsW5LybfNr(LuSwQjuWMLujjwu6PwIAkLrbCiChbLrb(Myfaz4uU5NsQovC(5KVr5LF5bWMHgzSj6zQtfKtI5PwqLLyoLMQhomhfzaeiOIlj1ckwkZukXsy0OStTYnvCj5xuUfxsrzMDQjvuQjwC(5DjFtm1Caks(5QGsMQeqRvSlWwl(Eb2v7cCW4f4KRGkU8mZlDXcQOulo1se7cCNaGd",
			},
		},
	},
	["login_squelch_time"] = 10,
}
