-------------------------------------------------------------------------------
-- Animations.lua
-- Built-in animation definitions for LibAnimate
-- Adapted from animate.css (https://animate.style) by Daniel Eden
--
-- Supported versions: Retail, TBC Anniversary, MoP Classic
-------------------------------------------------------------------------------

local lib = LibStub("LibAnimate")

-------------------------------------------------------------------------------
-- Back Entrances (defaultDuration=0.6, defaultDistance=300)
-------------------------------------------------------------------------------

lib:RegisterAnimation("backInDown", {
    type = "entrance",
    defaultDuration = 0.6,
    defaultDistance = 300,
    keyframes = {
        { progress = 0.0, translateY = 1.0, scale = 0.7, alpha = 0.7 },
        { progress = 0.8, translateY = 0, scale = 0.7, alpha = 0.7 },
        { progress = 1.0, scale = 1.0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("backInUp", {
    type = "entrance",
    defaultDuration = 0.6,
    defaultDistance = 300,
    keyframes = {
        { progress = 0.0, translateY = -1.0, scale = 0.7, alpha = 0.7 },
        { progress = 0.8, translateY = 0, scale = 0.7, alpha = 0.7 },
        { progress = 1.0, scale = 1.0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("backInLeft", {
    type = "entrance",
    defaultDuration = 0.6,
    defaultDistance = 300,
    keyframes = {
        { progress = 0.0, translateX = -1.0, scale = 0.7, alpha = 0.7 },
        { progress = 0.8, translateX = 0, scale = 0.7, alpha = 0.7 },
        { progress = 1.0, scale = 1.0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("backInRight", {
    type = "entrance",
    defaultDuration = 0.6,
    defaultDistance = 300,
    keyframes = {
        { progress = 0.0, translateX = 1.0, scale = 0.7, alpha = 0.7 },
        { progress = 0.8, translateX = 0, scale = 0.7, alpha = 0.7 },
        { progress = 1.0, scale = 1.0, alpha = 1.0 },
    },
})

-------------------------------------------------------------------------------
-- Back Exits (defaultDuration=0.6, defaultDistance=300)
-------------------------------------------------------------------------------

lib:RegisterAnimation("backOutDown", {
    type = "exit",
    defaultDuration = 0.6,
    defaultDistance = 300,
    keyframes = {
        { progress = 0.0, scale = 1.0, alpha = 1.0 },
        { progress = 0.2, translateY = 0, scale = 0.7, alpha = 0.7 },
        { progress = 1.0, translateY = -1.0, scale = 0.7, alpha = 0.7 },
    },
})

lib:RegisterAnimation("backOutUp", {
    type = "exit",
    defaultDuration = 0.6,
    defaultDistance = 300,
    keyframes = {
        { progress = 0.0, scale = 1.0, alpha = 1.0 },
        { progress = 0.2, translateY = 0, scale = 0.7, alpha = 0.7 },
        { progress = 1.0, translateY = 1.0, scale = 0.7, alpha = 0.7 },
    },
})

lib:RegisterAnimation("backOutLeft", {
    type = "exit",
    defaultDuration = 0.6,
    defaultDistance = 300,
    keyframes = {
        { progress = 0.0, scale = 1.0, alpha = 1.0 },
        { progress = 0.2, translateX = 0, scale = 0.7, alpha = 0.7 },
        { progress = 1.0, translateX = -1.0, scale = 0.7, alpha = 0.7 },
    },
})

lib:RegisterAnimation("backOutRight", {
    type = "exit",
    defaultDuration = 0.6,
    defaultDistance = 300,
    keyframes = {
        { progress = 0.0, scale = 1.0, alpha = 1.0 },
        { progress = 0.2, translateX = 0, scale = 0.7, alpha = 0.7 },
        { progress = 1.0, translateX = 1.0, scale = 0.7, alpha = 0.7 },
    },
})

-------------------------------------------------------------------------------
-- Sliding Entrances (defaultDuration=0.4, defaultDistance=200)
-------------------------------------------------------------------------------

lib:RegisterAnimation("slideInDown", {
    type = "entrance",
    defaultDuration = 0.4,
    defaultDistance = 200,
    keyframes = {
        { progress = 0.0, translateY = 1.0 },
        { progress = 1.0, translateY = 0 },
    },
})

lib:RegisterAnimation("slideInUp", {
    type = "entrance",
    defaultDuration = 0.4,
    defaultDistance = 200,
    keyframes = {
        { progress = 0.0, translateY = -1.0 },
        { progress = 1.0, translateY = 0 },
    },
})

lib:RegisterAnimation("slideInLeft", {
    type = "entrance",
    defaultDuration = 0.4,
    defaultDistance = 200,
    keyframes = {
        { progress = 0.0, translateX = -1.0 },
        { progress = 1.0, translateX = 0 },
    },
})

lib:RegisterAnimation("slideInRight", {
    type = "entrance",
    defaultDuration = 0.4,
    defaultDistance = 200,
    keyframes = {
        { progress = 0.0, translateX = 1.0 },
        { progress = 1.0, translateX = 0 },
    },
})

-------------------------------------------------------------------------------
-- Sliding Exits (defaultDuration=0.4, defaultDistance=200)
-------------------------------------------------------------------------------

lib:RegisterAnimation("slideOutDown", {
    type = "exit",
    defaultDuration = 0.4,
    defaultDistance = 200,
    keyframes = {
        { progress = 0.0, translateY = 0 },
        { progress = 1.0, translateY = -1.0 },
    },
})

lib:RegisterAnimation("slideOutUp", {
    type = "exit",
    defaultDuration = 0.4,
    defaultDistance = 200,
    keyframes = {
        { progress = 0.0, translateY = 0 },
        { progress = 1.0, translateY = 1.0 },
    },
})

lib:RegisterAnimation("slideOutLeft", {
    type = "exit",
    defaultDuration = 0.4,
    defaultDistance = 200,
    keyframes = {
        { progress = 0.0, translateX = 0 },
        { progress = 1.0, translateX = -1.0 },
    },
})

lib:RegisterAnimation("slideOutRight", {
    type = "exit",
    defaultDuration = 0.4,
    defaultDistance = 200,
    keyframes = {
        { progress = 0.0, translateX = 0 },
        { progress = 1.0, translateX = 1.0 },
    },
})

-------------------------------------------------------------------------------
-- Zooming Entrances (defaultDuration=0.5, defaultDistance=400)
-------------------------------------------------------------------------------

lib:RegisterAnimation("zoomIn", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0, scale = 0.3, alpha = 0 },
        { progress = 0.5, alpha = 1.0 },
        { progress = 1.0, scale = 1.0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("zoomInDown", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 400,
    keyframes = {
        { progress = 0.0, translateY = 1.0, scale = 0.1, alpha = 0, easing = { 0.55, 0.055, 0.675, 0.19 } },
        { progress = 0.6, translateY = -0.06, scale = 0.475, alpha = 1.0, easing = { 0.175, 0.885, 0.32, 1 } },
        { progress = 1.0, scale = 1.0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("zoomInUp", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 400,
    keyframes = {
        { progress = 0.0, translateY = -1.0, scale = 0.1, alpha = 0, easing = { 0.55, 0.055, 0.675, 0.19 } },
        { progress = 0.6, translateY = 0.06, scale = 0.475, alpha = 1.0, easing = { 0.175, 0.885, 0.32, 1 } },
        { progress = 1.0, scale = 1.0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("zoomInLeft", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 400,
    keyframes = {
        { progress = 0.0, translateX = -1.0, scale = 0.1, alpha = 0, easing = { 0.55, 0.055, 0.675, 0.19 } },
        { progress = 0.6, translateX = 0.01, scale = 0.475, alpha = 1.0, easing = { 0.175, 0.885, 0.32, 1 } },
        { progress = 1.0, scale = 1.0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("zoomInRight", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 400,
    keyframes = {
        { progress = 0.0, translateX = 1.0, scale = 0.1, alpha = 0, easing = { 0.55, 0.055, 0.675, 0.19 } },
        { progress = 0.6, translateX = -0.01, scale = 0.475, alpha = 1.0, easing = { 0.175, 0.885, 0.32, 1 } },
        { progress = 1.0, scale = 1.0, alpha = 1.0 },
    },
})

-------------------------------------------------------------------------------
-- Zooming Exits (defaultDuration=0.5, defaultDistance=400)
-------------------------------------------------------------------------------

lib:RegisterAnimation("zoomOut", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0, scale = 1.0, alpha = 1.0 },
        { progress = 0.5, scale = 0.3, alpha = 0 },
        { progress = 1.0, scale = 0.3, alpha = 0 },
    },
})

lib:RegisterAnimation("zoomOutDown", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 400,
    keyframes = {
        { progress = 0.0, scale = 1.0, alpha = 1.0, easing = { 0.55, 0.055, 0.675, 0.19 } },
        { progress = 0.4, translateY = 0.03, scale = 0.475, alpha = 1.0, easing = { 0.175, 0.885, 0.32, 1 } },
        { progress = 1.0, translateY = -1.0, scale = 0.1, alpha = 0 },
    },
})

lib:RegisterAnimation("zoomOutUp", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 400,
    keyframes = {
        { progress = 0.0, scale = 1.0, alpha = 1.0, easing = { 0.55, 0.055, 0.675, 0.19 } },
        { progress = 0.4, translateY = -0.03, scale = 0.475, alpha = 1.0, easing = { 0.175, 0.885, 0.32, 1 } },
        { progress = 1.0, translateY = 1.0, scale = 0.1, alpha = 0 },
    },
})

lib:RegisterAnimation("zoomOutLeft", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 400,
    keyframes = {
        { progress = 0.0, scale = 1.0, alpha = 1.0 },
        { progress = 0.4, translateX = 0.021, scale = 0.475, alpha = 1.0 },
        { progress = 1.0, translateX = -1.0, scale = 0.1, alpha = 0 },
    },
})

lib:RegisterAnimation("zoomOutRight", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 400,
    keyframes = {
        { progress = 0.0, scale = 1.0, alpha = 1.0 },
        { progress = 0.4, translateX = -0.021, scale = 0.475, alpha = 1.0 },
        { progress = 1.0, translateX = 1.0, scale = 0.1, alpha = 0 },
    },
})

-------------------------------------------------------------------------------
-- Fading Entrances
-------------------------------------------------------------------------------

lib:RegisterAnimation("fadeIn", {
    type = "entrance",
    defaultDuration = 0.3,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0, alpha = 0 },
        { progress = 1.0, alpha = 1.0 },
    },
})

-------------------------------------------------------------------------------
-- Fading Exits
-------------------------------------------------------------------------------

lib:RegisterAnimation("fadeOut", {
    type = "exit",
    defaultDuration = 0.3,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, alpha = 0 },
    },
})

-------------------------------------------------------------------------------
-- Move Entrances (smooth repositioning with easeOutQuad)
-------------------------------------------------------------------------------

lib:RegisterAnimation("moveUp", {
    type = "entrance",
    defaultDuration = 0.2,
    defaultDistance = 50,
    keyframes = {
        { progress = 0.0, translateY = -1.0, easing = "easeOutQuad" },
        { progress = 1.0, translateY = 0 },
    },
})

lib:RegisterAnimation("moveDown", {
    type = "entrance",
    defaultDuration = 0.2,
    defaultDistance = 50,
    keyframes = {
        { progress = 0.0, translateY = 1.0, easing = "easeOutQuad" },
        { progress = 1.0, translateY = 0 },
    },
})

lib:RegisterAnimation("moveLeft", {
    type = "entrance",
    defaultDuration = 0.2,
    defaultDistance = 50,
    keyframes = {
        { progress = 0.0, translateX = 1.0, easing = "easeOutQuad" },
        { progress = 1.0, translateX = 0 },
    },
})

lib:RegisterAnimation("moveRight", {
    type = "entrance",
    defaultDuration = 0.2,
    defaultDistance = 50,
    keyframes = {
        { progress = 0.0, translateX = -1.0, easing = "easeOutQuad" },
        { progress = 1.0, translateX = 0 },
    },
})

-------------------------------------------------------------------------------
-- Attention Seekers
-------------------------------------------------------------------------------

lib:RegisterAnimation("bounce", {
    type = "attention",
    defaultDuration = 1.0,
    defaultDistance = 30,
    keyframes = {
        { progress = 0.0,  translateY = 0, scale = 1.0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.2,  translateY = 0, scale = 1.0, easing = {0.755, 0.05, 0.855, 0.06} },
        { progress = 0.4,  translateY = 1.0, scale = 1.05, easing = {0.755, 0.05, 0.855, 0.06} },
        { progress = 0.43, translateY = 1.0, scale = 1.05, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.53, translateY = 0, scale = 1.0, easing = {0.755, 0.05, 0.855, 0.06} },
        { progress = 0.7,  translateY = 0.5, scale = 1.025 },
        { progress = 0.8,  translateY = 0, scale = 0.975, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.9,  translateY = 0.133, scale = 1.01 },
        { progress = 1.0,  translateY = 0, scale = 1.0 },
    },
})

lib:RegisterAnimation("flash", {
    type = "attention",
    defaultDuration = 1.0,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0,  alpha = 1.0 },
        { progress = 0.25, alpha = 0.0 },
        { progress = 0.5,  alpha = 1.0 },
        { progress = 0.75, alpha = 0.0 },
        { progress = 1.0,  alpha = 1.0 },
    },
})

lib:RegisterAnimation("pulse", {
    type = "attention",
    defaultDuration = 1.0,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0, scale = 1.0, easing = "easeInOutCubic" },
        { progress = 0.5, scale = 1.05 },
        { progress = 1.0, scale = 1.0 },
    },
})

lib:RegisterAnimation("rubberBand", {
    type = "attention",
    defaultDuration = 1.0,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0,  scale = 1.0 },
        { progress = 0.3,  scale = 1.25 },
        { progress = 0.4,  scale = 0.75 },
        { progress = 0.5,  scale = 1.15 },
        { progress = 0.65, scale = 0.95 },
        { progress = 0.75, scale = 1.05 },
        { progress = 1.0,  scale = 1.0 },
    },
})

lib:RegisterAnimation("shakeX", {
    type = "attention",
    defaultDuration = 1.0,
    defaultDistance = 10,
    keyframes = {
        { progress = 0.0,  translateX = 0 },
        { progress = 0.1,  translateX = -1.0 },
        { progress = 0.2,  translateX = 1.0 },
        { progress = 0.3,  translateX = -1.0 },
        { progress = 0.4,  translateX = 1.0 },
        { progress = 0.5,  translateX = -1.0 },
        { progress = 0.6,  translateX = 1.0 },
        { progress = 0.7,  translateX = -1.0 },
        { progress = 0.8,  translateX = 1.0 },
        { progress = 0.9,  translateX = -1.0 },
        { progress = 1.0,  translateX = 0 },
    },
})

lib:RegisterAnimation("shakeY", {
    type = "attention",
    defaultDuration = 1.0,
    defaultDistance = 10,
    keyframes = {
        { progress = 0.0,  translateY = 0 },
        { progress = 0.1,  translateY = 1.0 },
        { progress = 0.2,  translateY = -1.0 },
        { progress = 0.3,  translateY = 1.0 },
        { progress = 0.4,  translateY = -1.0 },
        { progress = 0.5,  translateY = 1.0 },
        { progress = 0.6,  translateY = -1.0 },
        { progress = 0.7,  translateY = 1.0 },
        { progress = 0.8,  translateY = -1.0 },
        { progress = 0.9,  translateY = 1.0 },
        { progress = 1.0,  translateY = 0 },
    },
})

lib:RegisterAnimation("headShake", {
    type = "attention",
    defaultDuration = 1.0,
    defaultDistance = 6,
    keyframes = {
        { progress = 0.0,   translateX = 0, easing = "easeInOutCubic" },
        { progress = 0.065, translateX = -1.0 },
        { progress = 0.185, translateX = 0.833 },
        { progress = 0.315, translateX = -0.5 },
        { progress = 0.435, translateX = 0.333 },
        { progress = 0.5,   translateX = 0 },
        { progress = 1.0,   translateX = 0 },
    },
})

lib:RegisterAnimation("tada", {
    type = "attention",
    defaultDuration = 1.0,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0,  scale = 1.0 },
        { progress = 0.1,  scale = 0.9 },
        { progress = 0.2,  scale = 0.9 },
        { progress = 0.3,  scale = 1.1 },
        { progress = 0.5,  scale = 1.1 },
        { progress = 0.7,  scale = 1.1 },
        { progress = 0.8,  scale = 1.1 },
        { progress = 0.9,  scale = 1.1 },
        { progress = 1.0,  scale = 1.0 },
    },
})

lib:RegisterAnimation("wobble", {
    type = "attention",
    defaultDuration = 1.0,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0,  translateX = 0 },
        { progress = 0.15, translateX = -0.25 },
        { progress = 0.3,  translateX = 0.2 },
        { progress = 0.45, translateX = -0.15 },
        { progress = 0.6,  translateX = 0.1 },
        { progress = 0.75, translateX = -0.05 },
        { progress = 1.0,  translateX = 0 },
    },
})

lib:RegisterAnimation("heartBeat", {
    type = "attention",
    defaultDuration = 1.3,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0,  scale = 1.0, easing = "easeInOutCubic" },
        { progress = 0.14, scale = 1.3 },
        { progress = 0.28, scale = 1.0 },
        { progress = 0.42, scale = 1.3 },
        { progress = 0.7,  scale = 1.0 },
        { progress = 1.0,  scale = 1.0 },
    },
})

-------------------------------------------------------------------------------
-- Bouncing Entrances
-------------------------------------------------------------------------------

lib:RegisterAnimation("bounceIn", {
    type = "entrance",
    defaultDuration = 0.75,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0,  scale = 0.3, alpha = 0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.2,  scale = 1.1, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.4,  scale = 0.9, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.6,  scale = 1.03, alpha = 1.0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.8,  scale = 0.97, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 1.0,  scale = 1.0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("bounceInDown", {
    type = "entrance",
    defaultDuration = 1.0,
    defaultDistance = 500,
    keyframes = {
        { progress = 0.0,  translateY = 1.0, alpha = 0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.6,  translateY = -0.05, alpha = 1.0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.75, translateY = 0.02, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.9,  translateY = -0.01, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 1.0,  translateY = 0 },
    },
})

lib:RegisterAnimation("bounceInLeft", {
    type = "entrance",
    defaultDuration = 1.0,
    defaultDistance = 500,
    keyframes = {
        { progress = 0.0,  translateX = -1.0, alpha = 0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.6,  translateX = 0.05, alpha = 1.0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.75, translateX = -0.02, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.9,  translateX = 0.01, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 1.0,  translateX = 0 },
    },
})

lib:RegisterAnimation("bounceInRight", {
    type = "entrance",
    defaultDuration = 1.0,
    defaultDistance = 500,
    keyframes = {
        { progress = 0.0,  translateX = 1.0, alpha = 0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.6,  translateX = -0.05, alpha = 1.0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.75, translateX = 0.02, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.9,  translateX = -0.01, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 1.0,  translateX = 0 },
    },
})

lib:RegisterAnimation("bounceInUp", {
    type = "entrance",
    defaultDuration = 1.0,
    defaultDistance = 500,
    keyframes = {
        { progress = 0.0,  translateY = -1.0, alpha = 0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.6,  translateY = 0.04, alpha = 1.0, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.75, translateY = -0.02, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 0.9,  translateY = 0.01, easing = {0.215, 0.61, 0.355, 1} },
        { progress = 1.0,  translateY = 0 },
    },
})

-------------------------------------------------------------------------------
-- Bouncing Exits
-------------------------------------------------------------------------------

lib:RegisterAnimation("bounceOut", {
    type = "exit",
    defaultDuration = 0.75,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0,  scale = 1.0, alpha = 1.0 },
        { progress = 0.2,  scale = 0.9 },
        { progress = 0.5,  scale = 1.1, alpha = 1.0 },
        { progress = 0.55, scale = 1.1, alpha = 1.0 },
        { progress = 1.0,  scale = 0.3, alpha = 0 },
    },
})

lib:RegisterAnimation("bounceOutDown", {
    type = "exit",
    defaultDuration = 1.0,
    defaultDistance = 500,
    keyframes = {
        { progress = 0.0,  translateY = 0, alpha = 1.0 },
        { progress = 0.2,  translateY = -0.02 },
        { progress = 0.4,  translateY = 0.04, alpha = 1.0 },
        { progress = 0.45, translateY = 0.04, alpha = 1.0 },
        { progress = 1.0,  translateY = -1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("bounceOutLeft", {
    type = "exit",
    defaultDuration = 1.0,
    defaultDistance = 500,
    keyframes = {
        { progress = 0.0,  translateX = 0, alpha = 1.0 },
        { progress = 0.2,  translateX = 0.04, alpha = 1.0 },
        { progress = 1.0,  translateX = -1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("bounceOutRight", {
    type = "exit",
    defaultDuration = 1.0,
    defaultDistance = 500,
    keyframes = {
        { progress = 0.0,  translateX = 0, alpha = 1.0 },
        { progress = 0.2,  translateX = -0.04, alpha = 1.0 },
        { progress = 1.0,  translateX = 1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("bounceOutUp", {
    type = "exit",
    defaultDuration = 1.0,
    defaultDistance = 500,
    keyframes = {
        { progress = 0.0,  translateY = 0, alpha = 1.0 },
        { progress = 0.2,  translateY = 0.02 },
        { progress = 0.4,  translateY = -0.04, alpha = 1.0 },
        { progress = 0.45, translateY = -0.04, alpha = 1.0 },
        { progress = 1.0,  translateY = 1.0, alpha = 0 },
    },
})

-------------------------------------------------------------------------------
-- Fading Entrances
-------------------------------------------------------------------------------

lib:RegisterAnimation("fadeInDown", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, translateY = 1.0, alpha = 0 },
        { progress = 1.0, translateY = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInDownBig", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 2000,
    keyframes = {
        { progress = 0.0, translateY = 1.0, alpha = 0 },
        { progress = 1.0, translateY = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInLeft", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, translateX = -1.0, alpha = 0 },
        { progress = 1.0, translateX = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInLeftBig", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 2000,
    keyframes = {
        { progress = 0.0, translateX = -1.0, alpha = 0 },
        { progress = 1.0, translateX = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInRight", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, translateX = 1.0, alpha = 0 },
        { progress = 1.0, translateX = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInRightBig", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 2000,
    keyframes = {
        { progress = 0.0, translateX = 1.0, alpha = 0 },
        { progress = 1.0, translateX = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInUp", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, translateY = -1.0, alpha = 0 },
        { progress = 1.0, translateY = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInUpBig", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 2000,
    keyframes = {
        { progress = 0.0, translateY = -1.0, alpha = 0 },
        { progress = 1.0, translateY = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInTopLeft", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, translateX = -1.0, translateY = 1.0, alpha = 0 },
        { progress = 1.0, translateX = 0, translateY = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInTopRight", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, translateX = 1.0, translateY = 1.0, alpha = 0 },
        { progress = 1.0, translateX = 0, translateY = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInBottomLeft", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, translateX = -1.0, translateY = -1.0, alpha = 0 },
        { progress = 1.0, translateX = 0, translateY = 0, alpha = 1.0 },
    },
})

lib:RegisterAnimation("fadeInBottomRight", {
    type = "entrance",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, translateX = 1.0, translateY = -1.0, alpha = 0 },
        { progress = 1.0, translateX = 0, translateY = 0, alpha = 1.0 },
    },
})

-------------------------------------------------------------------------------
-- Fading Exits
-------------------------------------------------------------------------------

lib:RegisterAnimation("fadeOutDown", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateY = -1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutDownBig", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 2000,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateY = -1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutLeft", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateX = -1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutLeftBig", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 2000,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateX = -1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutRight", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateX = 1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutRightBig", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 2000,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateX = 1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutUp", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateY = 1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutUpBig", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 2000,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateY = 1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutTopLeft", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateX = -1.0, translateY = 1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutTopRight", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateX = 1.0, translateY = 1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutBottomRight", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateX = 1.0, translateY = -1.0, alpha = 0 },
    },
})

lib:RegisterAnimation("fadeOutBottomLeft", {
    type = "exit",
    defaultDuration = 0.5,
    defaultDistance = 100,
    keyframes = {
        { progress = 0.0, alpha = 1.0 },
        { progress = 1.0, translateX = -1.0, translateY = -1.0, alpha = 0 },
    },
})

-------------------------------------------------------------------------------
-- Specials
-------------------------------------------------------------------------------

lib:RegisterAnimation("jackInTheBox", {
    type = "entrance",
    defaultDuration = 1.0,
    defaultDistance = 0,
    keyframes = {
        { progress = 0.0, scale = 0.1, alpha = 0 },
        { progress = 0.5, scale = 1.05 },
        { progress = 0.7, scale = 0.95 },
        { progress = 1.0, scale = 1.0, alpha = 1.0 },
    },
})
