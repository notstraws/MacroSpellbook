local _, smb = ...

-- The Druid page. See Config.lua for what each list does.
smb.classConfigs.DRUID = {
    categories = {
        { name = "Custom" },
        { name = "Damage", cooldownSteps = true, spells = {
            "Wrath",
            "Starfire",
            "Moonfire",
            "Insect Swarm",
            "Hurricane",
            "Shred",
            "Rake",
            "Rip",
            "Ferocious Bite",
            "Primal Bite",
            "Berserk",
            "Ravage",
            "Pounce",
            "Claw",
            "Maul",
            "Swipe",
            "Lacerate",
            "Faerie Fire",
            "Faerie Fire (Feral)",
        } },
        { name = "Healing", cooldownSteps = true, spells = {
            "Healing Touch",
            "Regrowth",
            "Rejuvenation",
            "Wild Growth",
            "Swiftmend",
            "Tranquility",
            "Nature's Swiftness",
            "Rebirth",
            "Revive",
        } },
        { name = "Utility", spells = {
            "Entangling Roots",
            "Hibernate",
            "Soothe Animal",
            "Bash",
            "Feral Charge",
            "Growl",
            "Challenging Roar",
            "Demoralizing Roar",
            "Cower",
            "Prowl",
            "Dash",
            "Enrage",
            "Tiger's Fury",
            "Remove Curse",
            "Abolish Poison",
            "Cure Poison",
            "Innervate",
            "Teleport: Moonglade",
            "Track Humanoids",
            "Bear Form",
            "Dire Bear Form",
            "Cat Form",
            "Travel Form",
            "Aquatic Form",
            "Moonkin Form",
        } },
        { name = "Buffs & Defence", sequence = true, spells = {
            "Mark of the Wild",
            "Gift of the Wild",
            "Thorns",
            "Omen of Clarity",
            "Nature's Grasp",
            "Barkskin",
            "Frenzied Regeneration",
        } },
    },

    mouseoverEnemy = {
        "Wrath",
        "Starfire",
        "Moonfire",
        "Insect Swarm",
        "Entangling Roots",
        "Faerie Fire",
        "Faerie Fire (Feral)",
        "Hibernate",
        "Soothe Animal",
    },

    mouseoverFriend = {
        "Healing Touch",
        "Regrowth",
        "Rejuvenation",
        "Wild Growth",
        "Swiftmend",
        "Rebirth",
        "Revive",
        "Remove Curse",
        "Abolish Poison",
        "Cure Poison",
        "Innervate",
        "Mark of the Wild",
        "Gift of the Wild",
        "Thorns",
    },

    cursor = {
        "Hurricane",
    },

    cooldowns = {
        "Nature's Swiftness",
        "Berserk",
    },

    channeled = {
        "Tranquility",
        "Hurricane",
    },

    stealth = {
        "Prowl",
    },

    extraSpells = {
        5487, -- Bear Form
        768, -- Cat Form
        1066, -- Aquatic Form
        8946, -- Cure Poison
        18960, -- Teleport: Moonglade
    },

    custom = {},
}
