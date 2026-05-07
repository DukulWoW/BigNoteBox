-- BigNoteBox Init.lua — Bootstrap namespace
-- This file loads FIRST. Creates the addon namespace and version constants.

local ADDON_NAME, BNB_NS = ...

BigNoteBox = BigNoteBox or {}
local BNB = BigNoteBox

BNB.ADDON_NAME = ADDON_NAME
BNB.ADDON_VERSION = "1.7.0"
BNB.NS = BNB_NS  -- private namespace for internal module communication

-- Version shorthand
BNB.version = BNB.ADDON_VERSION
