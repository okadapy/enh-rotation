-- Sample of WTF/Account/<name>/SavedVariables/WeakAuras.lua for build_spec (import-snapshots).

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
				["saved"] = {
					["swing"] = {
						["reset"] = {
							["stormstrike"] = true,
						},
					},
					["enhrotSnapshots"] = {
						{
							["S"] = {
								["now"] = 1234.5,
								["mode"] = "solo",
								["target"] = {
									["hp"] = 5000,
									["hpMax"] = 5000,
								},
							},
							["plan"] = {
								["value"] = 1800.25,
								["steps"] = {
									{
										["key"] = "stormstrike",
										["at"] = 0,
										["reason"] = "Maelstrom \"5\"",
									},
								},
							},
						}, -- [1]
						{
							["S"] = {
								["now"] = 1240,
							},
							["plan"] = {
								["value"] = 0,
								["steps"] = {
								},
							},
						}, -- [2]
					},
				},
			},
		},
	},
	["login_squelch_time"] = 10,
}
