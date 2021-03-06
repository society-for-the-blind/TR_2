local i = {}

-------------------------------------
-- `freeswitch.IVRMenu()` options --
------------------------------------
-- main,                  ?IVRMenu: the top level menu or nil if this is the top level one
-- name,                  ?string:  the name of the menu
-- greeting_sound,        ?string:  the menu prompt played the first time the menu is played
-- short_greeting_sound,  ?string:  the short version of the menu prompt played on subsequent loops
-- invalid_sound,         ?string:  the sound to play when an invalid entry/no entry is made
-- exit_sound,            ?string:  played when the menu is terminated
-- transfer_sound,        ?string:  the sound to play on transfer
-- confirm_macro,         ?string:  phrase macro name to confirm input
-- confirm_key,           ?string:  the key used to confirm a digit entry
-- tts_engine,            ?string:  the TTS engine to use for this menu
-- tts_voice,             ?string:  the TTS voice to use for this menu
-- confirm_attempts,      ?int:     number of times to prompt to confirm input before failure,
--                                  -1 for unlimited
-- inter_timeout,         ?int:     inter-digit timeout
-- digit_len,             ?int:     max number of digits
-- timeout,               ?int:     number of milliseconds to pause before looping
-- max_failures,          ?int:     threshold of failures before hanging up
-- max_timeouts)          ?int:     threshold of timeouts before hanging up,
--                                  -1 for unlimited?

-- WHY SO MANY MENUS?
-- See `main.lua`.

local registered_main_opts = { -- {{{2
  ["main"]                = nil,
  ["name"]                = "registered_main",
  ["greet_long"]          = "phrase:main_menu",
  ["greet_short"]         = "phrase:common_menu_items",
  ["invalid_sound"]       = "ivr/ivr-that_was_an_invalid_entry.wav",
  ["exit_sound"]          = "voicemail/vm-goodbye.wav",
  ["transfer_sound"]      = nil,
  ["confirm_macro"]       = nil,
  ["confirm_key"]         = nil,
  ["tts_engine"]          = "flite",
  ["tts_voice"]           = "rms",
  ["confirm_attempts"]    = "3",
  ["inter_digit_timeout"] = "2000",
  ["digit_len"]           = "1",
  ["timeout"]             = "10000",
  ["max_failures"]        = "3",
  ["max_timeouts"]        = "2"
}
i.registered_main_name = registered_main_opts["name"]

-- The only difference between  `unregistered_main_opts`
-- and  `registered_main_opts`  is  the  addition of the
-- word "unregistered" to the marked lines and `digit_len`
-- is 1 instead of 10.
--
-- (Lua  tables are  objects,  and  only the  reference
-- gets  copied, hence  the duplication  of the  entire
-- structure.  Could've gone  the way  of mutating  one
-- object, but  that would've gotten me  into all sorts
-- of messes.)
local unregistered_main_opts = { -- {{{2
  ["main"]                = nil,
  ["name"]                = "unregistered_main",                     --  *
  ["greet_long"]          = "phrase:unregistered_main_menu",         --  *
  ["greet_short"]         = "phrase:common_menu_items",              --  *
  ["invalid_sound"]       = "ivr/ivr-that_was_an_invalid_entry.wav",
  ["exit_sound"]          = "voicemail/vm-goodbye.wav",
  ["transfer_sound"]      = nil,
  ["confirm_macro"]       = nil,
  ["confirm_key"]         = nil,
  ["tts_engine"]          = "flite",
  ["tts_voice"]           = "rms",
  ["confirm_attempts"]    = "3",
  ["inter_digit_timeout"] = "2000",
                                                                     --  `digit_len` is 10 to allow entering the security code
  ["digit_len"]           = "10",                                    --  *
  ["timeout"]             = "10000",
  ["max_failures"]        = "3",
  ["max_timeouts"]        = "2"
}
i.unregistered_main_name = unregistered_main_opts["name"]

-- Same as `registered_main_opts` except for the marked ones.
local common_menu_opts = { -- {{{2
  ["main"]                = nil,
  ["name"]                = "common_menu",              -- *
  ["greet_long"]          = "phrase:common_menu_items", -- *
  ["greet_short"]         = "phrase:common_menu_items",
  ["invalid_sound"]       = "ivr/ivr-that_was_an_invalid_entry.wav",
  ["exit_sound"]          = "voicemail/vm-goodbye.wav",
  ["transfer_sound"]      = nil,
  ["confirm_macro"]       = nil,
  ["confirm_key"]         = nil,
  ["tts_engine"]          = "flite",
  ["tts_voice"]           = "rms",
  ["confirm_attempts"]    = "3",
  ["inter_digit_timeout"] = "2000",
  ["digit_len"]           = "1",
  ["timeout"]             = "10000",
  ["max_failures"]        = "3",
  ["max_timeouts"]        = "2"
}
i.common_menu_name = common_menu_opts["name"]

function get_IVRMenu(tbl) -- {{{2
  -- is return needed, or is it implicit in lua for the last statement?
  return freeswitch.IVRMenu(
    tbl["main"                ],
    tbl["name"                ],
    tbl["greet_long"          ],
    tbl["greet_short"         ],
    tbl["invalid_sound"       ],
    tbl["exit_sound"          ],
    tbl["transfer_sound"      ],
    tbl["confirm_macro"       ],
    tbl["confirm_key"         ],
    tbl["tts_engine"          ],
    tbl["tts_voice"           ],
    tbl["confirm_attempts"    ],
    tbl["inter_digit_timeout" ],
    tbl["digit_len"           ],
    tbl["timeout"             ],
    tbl["max_failures"        ],
    tbl["max_timeouts"        ]
  );
end

i.main = get_IVRMenu(registered_main_opts) -- {{{2

i.main:bindAction("menu-exec-app", "info", "1")
i.main:bindAction("menu-exec-app", "info", "2") 

i.unregistered_main = get_IVRMenu(unregistered_main_opts) -- {{{2

i.unregistered_main:bindAction("menu-exec-app", "info", "1")
i.unregistered_main:bindAction("menu-exec-app", "lua login.lua $1", "/^([0-9]{10})$/")

i.common_menu = get_IVRMenu(common_menu_opts) -- {{{2

i.common_menu:bindAction("menu-exec-app", "info", "1")
i.common_menu:bindAction("menu-exec-app", "info", "2") 

-- generate links and then strip the url scheme
-- local signed_url_without_url_scheme = ""

-- `playback` doesn't support mp3; need `mod_shout` to enable support
-- i.unregistered_main:bindAction("menu-exec-app", "playback shout://" .. signed_url_without_url_scheme, "3")

return i

-- VIM modeline
-- vim:set foldmethod=marker:
