--!strict
-- GameConfig.luau
-- Single source of truth for every tunable constant in the game.
-- Tweak values here and the whole game updates automatically.

local GameConfig = {

    -- =====================================================
    -- TIMING (seconds)
    -- =====================================================
    LOBBY_WAIT_AFTER_GAME   = 180,   -- 3 min lounge after a full round ends
    PREGAME_COUNTDOWN       = 30,    -- rooftop countdown before teams form
    TEAM_VOTE_DURATION      = 20,    -- color vote window
    MAP_LOAD_DELAY          = 3,     -- artificial loading screen buffer
    GAME_DURATION           = 420,   -- 7 minutes per game
    RESPAWN_DELAY           = 5,     -- seconds until player respawns
    POWERUP_RESPAWN_TIME    = 90,    -- center health block reappear interval
    FLAG_AUTO_RETURN_TIME   = 10,    -- dropped flag auto-returns after this
    ASSIST_WINDOW           = 10,    -- seconds after dealing damage to earn assist

    -- =====================================================
    -- SCORING
    -- =====================================================
    POINTS_TAKEDOWN         = 100,
    POINTS_ASSIST           = 30,
    POINTS_FLAG_CAPTURE     = 1000,
    NMZ_MULTIPLIER          = 2,     -- score multiplier inside No Man's Zone

    -- =====================================================
    -- ROUND STRUCTURE
    -- =====================================================
    GAMES_TO_WIN_ROUND      = 3,     -- first team to 3 game-wins takes the round
    MIN_PLAYERS_TO_START    = 1,    -- set to 2 for live game; 1 for solo testing

    -- =====================================================
    -- PLAYER / CHARACTER
    -- =====================================================
    DEFAULT_MAX_HEALTH      = 100,
    POWERUP_HEALTH_MULT     = 2.5,   -- center block grants 250 HP
    WALK_SPEED              = 16,
    ICE_SLIDE_SPEED         = 30,    -- top speed on ice
    ICE_FRICTION            = 0.05,
    NORMAL_FRICTION         = 0.3,

    -- =====================================================
    -- WEAPONS
    -- fireRate   = seconds between shots
    -- spread     = random angle offset (radians)
    -- speed      = projectile studs/sec (0 = hitscan)
    -- paintColor = splat color on surfaces
    -- =====================================================
    WEAPONS = {
        PaintballGun = {
            displayName = "Paintball Gun",
            damage      = 34,       -- 3 shots to eliminate
            fireRate    = 0.28,
            ammo        = 12,
            reloadTime  = 1.8,
            spread      = 0.04,
            speed       = 200,
            isHitscan   = false,
            paintColor  = Color3.fromRGB(255, 80, 0),
        },
        SniperPaintball = {
            displayName = "Sniper",
            damage      = 80,       -- 2 shots to eliminate
            fireRate    = 1.6,
            ammo        = 5,
            reloadTime  = 2.5,
            spread      = 0.001,
            speed       = 0,        -- hitscan
            isHitscan   = true,
            paintColor  = Color3.fromRGB(0, 200, 255),
        },
        ShotgunPaintball = {
            displayName = "Shotgun",
            damage      = 12,       -- per pellet; 6 pellets = potential 72 dmg
            pellets     = 6,
            fireRate    = 1.0,
            ammo        = 6,
            reloadTime  = 2.0,
            spread      = 0.14,
            speed       = 160,
            isHitscan   = false,
            paintColor  = Color3.fromRGB(200, 0, 200),
        },
    },

    -- Default weapon every player spawns with
    DEFAULT_WEAPON = "PaintballGun",

    -- =====================================================
    -- MAP SCALING
    -- Players < threshold → use that size entry
    -- =====================================================
    MAP_SIZES = {
        { threshold = 10,         size = 400,  label = "SMALL"  },
        { threshold = 20,         size = 700,  label = "MEDIUM" },
        { threshold = math.huge,  size = 1000, label = "LARGE"  },
    },

    -- Zone fractions (of half-map length from the castle back wall)
    --  Castle:    0–20%  of half-map
    --  Cover:    20–50%  of half-map  (i.e. to midpoint)
    --  NMZ starts at 50% from each side → central 20% of full map (10% each way from absolute center)
    CASTLE_DEPTH_FRAC   = 0.20,
    COVER_DEPTH_FRAC    = 0.50,

    -- =====================================================
    -- TEAM COLORS (vote options)
    -- =====================================================
    TEAM_COLOR_OPTIONS = {
        { name = "Crimson",     color = BrickColor.new("Crimson"),       rgb = Color3.fromRGB(220,  20,  60) },
        { name = "Royal Blue",  color = BrickColor.new("Royal blue"),    rgb = Color3.fromRGB( 30,  60, 200) },
        { name = "Lime Green",  color = BrickColor.new("Lime green"),    rgb = Color3.fromRGB(  0, 200,  50) },
        { name = "Purple",      color = BrickColor.new("Alder"),         rgb = Color3.fromRGB(140,   0, 200) },
        { name = "Orange",      color = BrickColor.new("Bright orange"), rgb = Color3.fromRGB(255, 140,   0) },
        { name = "Hot Pink",    color = BrickColor.new("Hot pink"),      rgb = Color3.fromRGB(255,  20, 147) },
        { name = "Teal",        color = BrickColor.new("Teal"),          rgb = Color3.fromRGB(  0, 170, 170) },
        { name = "Gold",        color = BrickColor.new("Bright yellow"), rgb = Color3.fromRGB(218, 170,   0) },
    },

    -- =====================================================
    -- SKILL FORMULA WEIGHTS
    -- Score = (Takedowns×T + Assists×A + Flags×F - Deaths×D) / max(1, minutes)
    -- =====================================================
    SKILL_TAKEDOWN_WEIGHT   = 3.0,
    SKILL_ASSIST_WEIGHT     = 1.0,
    SKILL_FLAG_WEIGHT       = 10.0,
    SKILL_DEATH_PENALTY     = 0.5,

    -- =====================================================
    -- LOBBY
    -- =====================================================
    LOBBY_SPAWN_Y           = 50,    -- height of lobby floor
    ROOFTOP_Y               = 120,   -- height of rooftop where countdown happens
}

return GameConfig
