-- BigNoteBox Features/HtmlTemplate.lua
-- Stylized HTML export template (book/tome design).
-- Lazy-loaded: the template string is built on first call to BNB.HtmlTemplate.Get().
--
-- The template contains four placeholders replaced at export time:
--   %%TITLE%%      -> note title (HTML-escaped, used in <title> tag)
--   %%META%%       -> <meta> tags block
--   %%NOTE_TITLE%% -> note title (HTML, may include colour styling)
--   %%NOTE_BODY%%  -> converted note body HTML
--
-- Public API:
--   BNB.HtmlTemplate.Get() -> string (the full template)

local BNB = BigNoteBox
BNB.HtmlTemplate = BNB.HtmlTemplate or {}

local _cached = nil

function BNB.HtmlTemplate.Get()
    if _cached then return _cached end
    _cached = [=[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>%%TITLE%%</title>
%%META%%
<style>
/* ---------- Fonts ---------- */
@import url('https://fonts.googleapis.com/css2?family=Cinzel:wght@400;600;700;900&family=Cinzel+Decorative:wght@400;700;900&family=IM+Fell+English:ital@0;1&family=IM+Fell+English+SC&display=swap');

/* ---------- Tokens ---------- */
:root {
  --ink:          #2a1a0b;
  --ink-soft:     #4a3522;
  --gold:         #e9c97a;
  --gold-bright:  #ffe9a8;
  --gold-deep:    #9a6f2a;
  --gold-shadow:  #4a330f;
  --page-w: min(97vw, 1200px);
  --page-h: min(88vh, 960px);
}

* { box-sizing: border-box; }
html, body {
  margin: 0; padding: 0;
  width: 100%; height: 100%;
  overflow: hidden;
  background: #060403;
  font-family: 'IM Fell English', Georgia, serif;
  color: var(--ink);
  cursor: default;
}

/* ── SCENE / FIRE / EMBERS ─────────────────────────── */
.scene {
  position: fixed; inset: 0;
  background:
    radial-gradient(ellipse 95% 70% at 50% 115%,
      rgba(255,120,35,.55) 0%, rgba(180,60,20,.45) 22%,
      rgba(80,28,10,.35) 48%, transparent 72%),
    radial-gradient(ellipse at 50% 30%, #251b10 0%, #120a05 45%, #050303 100%);
  overflow: hidden;
  z-index: 0;
}
.scene::before {
  content: '';
  position: absolute; inset: -20%;
  background-image:
    radial-gradient(1px 1px at 10% 20%, rgba(255,220,150,.7), transparent),
    radial-gradient(1px 1px at 80% 40%, rgba(255,200,120,.5), transparent),
    radial-gradient(1px 1px at 30% 85%, rgba(255,220,150,.6), transparent),
    radial-gradient(1px 1px at 15% 55%, rgba(255,230,180,.3), transparent);
  background-size: 600px 600px, 700px 700px, 800px 800px, 900px 900px;
  animation: drift 120s linear infinite;
  opacity: .6;
}
@keyframes drift { to { transform: translate(-80px,-120px); } }

.fire-glow {
  position: fixed;
  left: 50%; bottom: -25vh;
  width: 180vw; height: 120vh;
  transform: translateX(-50%);
  background: radial-gradient(ellipse 55% 75% at 50% 100%,
    rgba(255,190,80,1) 0%, rgba(255,130,35,.85) 12%,
    rgba(220,80,25,.6) 28%, rgba(140,45,15,.35) 48%, transparent 72%);
  filter: blur(28px);
  mix-blend-mode: screen;
  pointer-events: none; z-index: 0;
  animation: fire-pulse 3.8s ease-in-out infinite;
}
.fire-glow.b {
  left: 22%; bottom: -32vh; width: 95vw; height: 100vh;
  background: radial-gradient(ellipse 60% 80% at 50% 100%,
    rgba(255,215,110,.9) 0%, rgba(245,140,45,.7) 22%,
    rgba(170,65,20,.4) 44%, transparent 72%);
  animation: fire-pulse-b 4.4s ease-in-out infinite -1.2s;
}
.fire-glow.c {
  left: 78%; bottom: -30vh; width: 90vw; height: 100vh;
  background: radial-gradient(ellipse 60% 80% at 50% 100%,
    rgba(255,200,90,.95) 0%, rgba(235,105,30,.72) 22%,
    rgba(155,55,18,.4) 44%, transparent 72%);
  animation: fire-pulse-c 3.6s ease-in-out infinite -2.2s;
}
@keyframes fire-pulse {
  0%,100% { opacity:.9;  transform:translateX(-50%) scaleY(1) scaleX(1); }
  25%      { opacity:1.2; transform:translateX(-50%) scaleY(1.16) scaleX(.93); }
  50%      { opacity:.95; transform:translateX(-50%) scaleY(.9) scaleX(1.08); }
  75%      { opacity:1.15;transform:translateX(-50%) scaleY(1.2) scaleX(.96); }
}
@keyframes fire-pulse-b {
  0%,100% { opacity:.8;  transform:scaleY(1); }
  40%     { opacity:1.2; transform:scaleY(1.22) scaleX(.92); }
}
@keyframes fire-pulse-c {
  0%,100% { opacity:.85; transform:scaleY(1); }
  35%     { opacity:1.25; transform:scaleY(1.18) scaleX(.94); }
}
.ember {
  position: absolute;
  border-radius: 50%;
  background: radial-gradient(circle, #ffd98a, #e9a24a 40%, transparent 70%);
  box-shadow: 0 0 8px #ffc16b;
  animation: float-up linear infinite;
  pointer-events: none;
}
@keyframes float-up {
  0%   { transform: translateY(100vh) translateX(0) scale(.5); opacity: 0; }
  10%  { opacity: 1; }
  90%  { opacity: 1; }
  100% { transform: translateY(-10vh) translateX(var(--dx, 30px)) scale(1); opacity: 0; }
}

/* ── BOOK SHELL ────────────────────────────────────── */
.book-shell {
  position: fixed; inset: 0;
  display: flex; align-items: center; justify-content: center;
  z-index: 1;
}

.book {
  position: relative;
  width: var(--page-w);
  height: var(--page-h);
  background:
    repeating-linear-gradient(87deg, transparent 0 38px, rgba(0,0,0,.18) 38px 39px, transparent 39px 78px),
    repeating-linear-gradient(2deg, transparent 0 60px, rgba(255,180,80,.05) 60px 61px),
    radial-gradient(ellipse 28% 14% at 16% 20%, rgba(100,58,18,.6), transparent),
    radial-gradient(ellipse 20% 10% at 80% 75%, rgba(60,32,10,.7), transparent),
    radial-gradient(ellipse 14% 7%  at 84% 18%, rgba(28,14,5,.8),  transparent),
    radial-gradient(ellipse 12% 6%  at 10% 84%, rgba(22,11,4,.75), transparent),
    linear-gradient(158deg, #321f0e 0%, #1c1009 30%, #0e0804 58%, #1a1008 80%, #261508 100%);
  box-shadow:
    0 0 120px rgba(255,140,40,.22),
    0 0 0 1px #000,
    0 28px 80px rgba(0,0,0,.98),
    0 55px 160px rgba(0,0,0,.9),
    inset 0 3px 0 rgba(255,218,130,.32),
    inset 0 1px 0 rgba(255,255,255,.06),
    inset 3px 0 0 rgba(255,210,120,.14),
    inset -3px 0 0 rgba(255,210,120,.08),
    inset 0 -3px 0 rgba(0,0,0,.8),
    inset 0 0 80px rgba(0,0,0,.6);
  border-radius: 4px 10px 10px 4px;
}

/* Embossed gold border */
.book::before {
  content: '';
  position: absolute;
  inset: 32px 36px 36px 74px;
  box-shadow:
    0 0 0 1px rgba(0,0,0,.95),
    0 0 0 2px rgba(255,218,130,.55),
    0 0 0 3px rgba(154,111,42,.8),
    0 0 0 4px rgba(80,50,15,.9),
    0 0 0 5px rgba(233,201,122,.22),
    inset 0 2px 8px rgba(0,0,0,.6),
    inset 2px 0 8px rgba(0,0,0,.4),
    0 0 24px rgba(233,201,122,.14);
  pointer-events: none;
  z-index: 2;
}

/* Fine inset filigree line */
.book::after {
  content: '';
  position: absolute;
  inset: 44px 50px 50px 88px;
  box-shadow:
    0 0 0 1px rgba(0,0,0,.8),
    0 0 0 1.5px rgba(233,201,122,.4),
    0 0 0 2.5px rgba(0,0,0,.6);
  pointer-events: none;
  z-index: 2;
}

/* ── SPINE ─────────────────────────────────────────── */
.book-spine {
  position: absolute;
  top: 6px; bottom: 6px; left: 6px;
  width: 72px;
  background:
    repeating-linear-gradient(180deg,
      transparent 0 8px, rgba(255,200,100,.07) 8px 9px,
      transparent 9px 18px),
    linear-gradient(90deg, #060402 0%, #1a0f07 30%, #2e1c0c 55%, #1a0e06 75%, #060402 100%);
  border-right: 1px solid rgba(233,201,122,.22);
  border-radius: 3px 0 0 3px;
  z-index: 3;
}
.book-spine::before, .book-spine::after {
  content: '';
  position: absolute; left: 0; right: 0; height: 16px;
  background:
    linear-gradient(180deg,
      rgba(255,235,160,.08) 0%,
      #c99a45 18%, #f4d98b 50%, #c99a45 82%,
      rgba(60,38,12,.8) 100%);
  border-top: 1px solid rgba(255,230,140,.35);
  border-bottom: 1px solid rgba(0,0,0,.8);
  box-shadow: inset 0 1px 0 rgba(255,240,190,.2);
}
.book-spine::before { top: 12%; }
.book-spine::after  { bottom: 12%; }

.book-spine-title {
  position: absolute;
  top: 30%; left: 50%;
  transform: translate(-50%, -50%);
  writing-mode: vertical-rl;
  text-orientation: mixed;
  font-family: 'Cinzel Decorative', serif;
  font-size: 11px; font-weight: 700;
  letter-spacing: .3em;
  color: var(--gold);
  text-shadow: 0 1px 3px rgba(0,0,0,.9), 0 0 12px rgba(233,201,122,.4);
  z-index: 4;
  pointer-events: none;
  white-space: nowrap;
}

.book-spine-emblem {
  position: absolute;
  left: 50%; top: 72%;
  transform: translate(-50%, -50%);
  width: 36px; height: 36px;
  border-radius: 50%;
  background: radial-gradient(circle at 35% 30%,
    #fffae8 0%, #f4d98b 22%, #c99a45 48%, #7a5a1e 74%, #2a1a08 100%);
  box-shadow:
    0 3px 10px rgba(0,0,0,.85),
    inset 0 2px 4px rgba(255,245,200,.6),
    inset 0 -2px 5px rgba(0,0,0,.6);
  z-index: 4;
  display: grid; place-items: center;
}
.book-spine-emblem::after {
  content: '';
  position: absolute; inset: 8px;
  border-radius: 50%;
  border: 1px solid rgba(80,50,10,.5);
  box-shadow: 0 0 0 2px rgba(233,201,122,.2);
}
.book-spine-rune {
  font-family: 'Cinzel', serif;
  font-size: 14px; font-weight: 900;
  color: rgba(30,15,5,.7);
  text-shadow: 0 1px 0 rgba(255,240,190,.4);
  position: relative; z-index: 5;
}

/* ── CORNER ORNAMENTS ─────────────────────────────── */
.corner-ornament {
  position: absolute;
  width: 185px; height: 185px;
  pointer-events: none;
  z-index: 10;
  overflow: visible;
}
.corner-ornament.tl { top: 0;  left: 8px;  transform: none; }
.corner-ornament.tr { top: 0;  right: 8px; transform: scaleX(-1); transform-origin: 50% 50%; }
.corner-ornament.bl { bottom: 0; left: 8px;  transform: scaleY(-1); transform-origin: 50% 50%; }
.corner-ornament.br { bottom: 0; right: 8px; transform: scale(-1,-1); transform-origin: 50% 50%; }

/* ── STUDS ────────────────────────────────────────── */
.book-studs-top, .book-studs-bottom, .book-studs-right {
  position: absolute;
  z-index: 6; pointer-events: none;
  display: flex; align-items: center;
}
.book-studs-top    { top: 13px;    left: 90px; right: 90px;  height: 12px; justify-content: space-around; }
.book-studs-bottom { bottom: 13px; left: 90px; right: 90px;  height: 12px; justify-content: space-around; }
.book-studs-right  { right: 14px;  top: 90px;  bottom: 90px; width: 12px;  flex-direction: column; justify-content: space-around; }

.stud {
  width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0;
  background: radial-gradient(circle at 32% 26%,
    #fffae0 0%, #f4d98b 18%, #c99a45 42%, #7a5220 68%, #2a1508 100%);
  box-shadow:
    0 2px 7px rgba(0,0,0,.9),
    0 1px 3px rgba(0,0,0,.7),
    inset 0 2px 3px rgba(255,248,210,.65),
    inset 0 -2px 3px rgba(0,0,0,.6),
    0 0 0 1px rgba(0,0,0,.6);
}

/* ── CLASP ────────────────────────────────────────── */
.book-clasp {
  position: absolute;
  right: -6px; top: 50%; transform: translateY(-50%);
  width: 20px; height: 70px;
  z-index: 8;
  background: linear-gradient(90deg,
    #3a2410 0%, #8a6030 30%, #c99a45 50%, #8a6030 70%, #2a1808 100%);
  border: 1px solid var(--gold-shadow);
  border-radius: 0 4px 4px 0;
  box-shadow: 2px 0 8px rgba(0,0,0,.6);
  display: flex; align-items: center; justify-content: center;
}
.book-clasp::before {
  content: '';
  width: 10px; height: 10px; border-radius: 50%;
  background: radial-gradient(circle at 35% 30%,
    #fffae8 0%, #f4d98b 25%, #c99a45 55%, #5a3e18 100%);
  box-shadow: 0 2px 6px rgba(0,0,0,.7), inset 0 1px 3px rgba(255,245,200,.6);
}

/* ── PAGE INNER ───────────────────────────────────── */
.page-inner {
  position: absolute;
  inset: 50px 55px 55px 90px;
  overflow: hidden;
  z-index: 1;
  background:
    radial-gradient(ellipse at 50% 50%, transparent 40%, rgba(70,40,15,.5) 85%, rgba(30,15,5,.8) 100%),
    #e0c888;
}

/* ── NOTE CONTENT ─────────────────────────────────── */
.note-content {
  position: absolute; inset: 0;
  padding: 40px 52px 48px 52px;
  display: flex; flex-direction: column; gap: 18px;
  overflow-y: auto;
  /* hide scrollbar but allow scroll */
  scrollbar-width: none;
}
.note-content::-webkit-scrollbar { display: none; }

.note-title {
  font-family: 'Cinzel Decorative', serif;
  font-weight: 700;
  font-size: clamp(22px, 3vw, 38px);
  line-height: 1.2;
  letter-spacing: .06em;
  color: var(--ink);
  text-shadow: 0 1px 0 rgba(255,240,200,.5);
  margin: 0;
  padding-bottom: 14px;
  border-bottom: none;
  position: relative;
}
.note-title::after {
  content: '';
  display: block;
  margin-top: 14px;
  height: 12px;
  background:
    linear-gradient(90deg, transparent, var(--gold-deep) 20%, var(--gold) 50%, var(--gold-deep) 80%, transparent) center / 100% 1px no-repeat,
    radial-gradient(circle at 50% 50%, var(--gold) 0 2.5px, transparent 3.5px) center / 100% 100% no-repeat;
}

.note-body {
  font-family: 'IM Fell English', Georgia, serif;
  font-size: 15px;
  line-height: 1.7;
  color: var(--ink);
  flex: 1;
  text-wrap: pretty;
}
.note-body p { margin: 0 0 1em; }
.note-body p:last-child { margin-bottom: 0; }
.note-body h2 {
  font-family: 'Cinzel', serif;
  font-size: 16px; font-weight: 700;
  letter-spacing: .08em;
  margin: 1.4em 0 .5em;
  color: var(--ink);
}
.note-body h3 {
  font-family: 'Cinzel', serif;
  font-size: 13px; font-weight: 600;
  letter-spacing: .06em;
  margin: 1.2em 0 .4em;
}
.note-body ul, .note-body ol {
  padding-left: 1.6em;
  margin: .5em 0 1em;
}
.note-body li { margin-bottom: .35em; }
.note-body strong { font-weight: 700; color: #1a0e04; }
.note-body em { font-style: italic; color: var(--ink-soft); }
.note-body code {
  font-family: 'Courier New', monospace;
  font-size: .88em;
  background: rgba(42,20,10,.12);
  border: 1px solid rgba(154,111,42,.3);
  padding: 1px 5px; border-radius: 2px;
}
.note-body blockquote {
  border-left: 3px solid var(--gold-deep);
  margin: 0 0 1em 0;
  padding: 6px 16px;
  color: var(--ink-soft);
  font-style: italic;
}

/* page vignette overlay (cosmetic, on top of content) */
.page-vignette {
  position: absolute; inset: 0;
  background: radial-gradient(ellipse at 50% 50%, transparent 55%, rgba(70,40,15,.45) 100%);
  pointer-events: none; z-index: 2;
}
</style>
</head>
<body>

<div class="book-shell">
  <div class="book">

    <!-- Spine -->
    <div class="book-spine">
      <div class="book-spine-title">BigNoteBox</div>
      <div class="book-spine-emblem"><span class="book-spine-rune">✦</span></div>
    </div>

    <!-- Corner ornaments (pre-rendered SVG, no JS required) -->
    <!-- TOP LEFT -->
    <svg class="corner-ornament tl" viewBox="0 0 185 185" overflow="visible">
      <defs>
        <radialGradient id="co-tl-boss" cx="34%" cy="28%" r="68%">
          <stop offset="0%"   stop-color="#fffde8"/>
          <stop offset="14%"  stop-color="#f4d98b"/>
          <stop offset="44%"  stop-color="#c99a45"/>
          <stop offset="72%"  stop-color="#7a5220"/>
          <stop offset="100%" stop-color="#1e1006"/>
        </radialGradient>
        <radialGradient id="co-tl-gem" cx="34%" cy="28%" r="62%">
          <stop offset="0%"   stop-color="#4a2814"/>
          <stop offset="45%"  stop-color="#1a0d04"/>
          <stop offset="100%" stop-color="#070402"/>
        </radialGradient>
        <linearGradient id="co-tl-armH" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#1a0d04"/>
          <stop offset="28%"  stop-color="#c99a45"/>
          <stop offset="50%"  stop-color="#f4d98b"/>
          <stop offset="72%"  stop-color="#c99a45"/>
          <stop offset="100%" stop-color="#1a0d04"/>
        </linearGradient>
        <linearGradient id="co-tl-armV" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%"   stop-color="#1a0d04"/>
          <stop offset="28%"  stop-color="#c99a45"/>
          <stop offset="50%"  stop-color="#f4d98b"/>
          <stop offset="72%"  stop-color="#c99a45"/>
          <stop offset="100%" stop-color="#1a0d04"/>
        </linearGradient>
        <filter id="co-tl-ds"><feDropShadow dx="1" dy="4" stdDeviation="5" flood-color="#000" flood-opacity="0.9"/></filter>
      </defs>
      <!-- horizontal arm -->
      <rect x="96" y="55" width="89" height="14" rx="2" fill="rgba(0,0,0,0.65)" transform="translate(2,4)"/>
      <rect x="96" y="55" width="89" height="14" rx="2" fill="url(#co-tl-armH)" filter="url(#co-tl-ds)"/>
      <rect x="98" y="56" width="85" height="1.5" rx="0.5" fill="rgba(255,248,210,0.5)"/>
      <rect x="98" y="60" width="85" height="1"   rx="0.5" fill="rgba(255,248,210,0.28)"/>
      <rect x="98" y="66" width="85" height="1.5" rx="0.5" fill="rgba(0,0,0,0.45)"/>
      <rect x="118" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="118.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="138" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="138.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="158" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="158.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="178" y="52" width="7" height="20" rx="2" fill="url(#co-tl-armH)" filter="url(#co-tl-ds)"/>
      <rect x="179" y="53" width="2.5" height="18" rx="1" fill="rgba(255,248,200,0.4)"/>
      <!-- vertical arm -->
      <rect x="55" y="96" width="14" height="89" rx="2" fill="rgba(0,0,0,0.65)" transform="translate(3,2)"/>
      <rect x="55" y="96" width="14" height="89" rx="2" fill="url(#co-tl-armV)" filter="url(#co-tl-ds)"/>
      <rect x="56" y="98" width="1.5" height="85" rx="0.5" fill="rgba(255,248,210,0.5)"/>
      <rect x="61" y="98" width="1"   height="85" rx="0.5" fill="rgba(255,248,210,0.28)"/>
      <rect x="66" y="98" width="1.5" height="85" rx="0.5" fill="rgba(0,0,0,0.45)"/>
      <rect x="56" y="118" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="118.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="56" y="138" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="138.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="56" y="158" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="158.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="52" y="178" width="20" height="7" rx="2" fill="url(#co-tl-armV)" filter="url(#co-tl-ds)"/>
      <rect x="53" y="179" width="18" height="2.5" rx="1" fill="rgba(255,248,200,0.4)"/>
      <!-- boss -->
      <circle cx="63" cy="63" r="57" fill="rgba(0,0,0,0.75)" transform="translate(2,5)"/>
      <circle cx="63" cy="63" r="57" fill="url(#co-tl-boss)" filter="url(#co-tl-ds)"/>
      <circle cx="63" cy="63" r="52" fill="none" stroke="rgba(0,0,0,0.55)" stroke-width="2"/>
      <circle cx="63" cy="63" r="50" fill="none" stroke="rgba(255,235,155,0.28)" stroke-width="0.75"/>
      <circle cx="63" cy="63" r="40" fill="none" stroke="rgba(0,0,0,0.45)" stroke-width="1.5"/>
      <circle cx="63" cy="63" r="38.5" fill="none" stroke="rgba(255,235,155,0.22)" stroke-width="0.5"/>
      <polygon points="63,34 84,63 63,92 42,63" fill="none" stroke="rgba(20,12,4,0.7)" stroke-width="2"/>
      <polygon points="63,38 80,63 63,88 46,63" fill="none" stroke="rgba(233,201,122,0.32)" stroke-width="0.75"/>
      <line x1="63" y1="36" x2="63" y2="90" stroke="rgba(20,12,4,0.35)" stroke-width="0.75"/>
      <line x1="36" y1="63" x2="90" y2="63" stroke="rgba(20,12,4,0.35)" stroke-width="0.75"/>
      <circle cx="63" cy="38" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="62" cy="37" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="88" cy="63" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="87" cy="62" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="63" cy="88" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="62" cy="87" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="38" cy="63" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="37" cy="62" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="63" cy="63" r="20" fill="url(#co-tl-gem)" stroke="#9a6f2a" stroke-width="1.5"/>
      <circle cx="63" cy="63" r="18" fill="none" stroke="rgba(233,201,122,0.35)" stroke-width="0.75"/>
      <ellipse cx="57" cy="56" rx="5" ry="3.5" fill="rgba(255,245,210,0.22)" transform="rotate(-25,57,56)"/>
      <circle cx="63" cy="63" r="9"  fill="none" stroke="rgba(154,111,42,0.6)" stroke-width="1"/>
      <circle cx="63" cy="63" r="5"  fill="#c99a45" stroke="rgba(0,0,0,0.5)" stroke-width="0.75"/>
      <circle cx="61.5" cy="61.5" r="2" fill="rgba(255,248,220,0.75)"/>
    </svg>

    <!-- TOP RIGHT (mirrored horizontally) -->
    <svg class="corner-ornament tr" viewBox="0 0 185 185" overflow="visible">
      <defs>
        <radialGradient id="co-tr-boss" cx="34%" cy="28%" r="68%">
          <stop offset="0%"   stop-color="#fffde8"/><stop offset="14%"  stop-color="#f4d98b"/>
          <stop offset="44%"  stop-color="#c99a45"/><stop offset="72%"  stop-color="#7a5220"/>
          <stop offset="100%" stop-color="#1e1006"/>
        </radialGradient>
        <radialGradient id="co-tr-gem" cx="34%" cy="28%" r="62%">
          <stop offset="0%"   stop-color="#4a2814"/><stop offset="45%"  stop-color="#1a0d04"/>
          <stop offset="100%" stop-color="#070402"/>
        </radialGradient>
        <linearGradient id="co-tr-armH" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#1a0d04"/><stop offset="28%"  stop-color="#c99a45"/>
          <stop offset="50%"  stop-color="#f4d98b"/><stop offset="72%"  stop-color="#c99a45"/>
          <stop offset="100%" stop-color="#1a0d04"/>
        </linearGradient>
        <linearGradient id="co-tr-armV" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%"   stop-color="#1a0d04"/><stop offset="28%"  stop-color="#c99a45"/>
          <stop offset="50%"  stop-color="#f4d98b"/><stop offset="72%"  stop-color="#c99a45"/>
          <stop offset="100%" stop-color="#1a0d04"/>
        </linearGradient>
        <filter id="co-tr-ds"><feDropShadow dx="1" dy="4" stdDeviation="5" flood-color="#000" flood-opacity="0.9"/></filter>
      </defs>
      <rect x="96" y="55" width="89" height="14" rx="2" fill="rgba(0,0,0,0.65)" transform="translate(2,4)"/>
      <rect x="96" y="55" width="89" height="14" rx="2" fill="url(#co-tr-armH)" filter="url(#co-tr-ds)"/>
      <rect x="98" y="56" width="85" height="1.5" rx="0.5" fill="rgba(255,248,210,0.5)"/>
      <rect x="98" y="60" width="85" height="1"   rx="0.5" fill="rgba(255,248,210,0.28)"/>
      <rect x="98" y="66" width="85" height="1.5" rx="0.5" fill="rgba(0,0,0,0.45)"/>
      <rect x="118" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="118.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="138" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="138.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="158" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="158.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="178" y="52" width="7" height="20" rx="2" fill="url(#co-tr-armH)" filter="url(#co-tr-ds)"/>
      <rect x="179" y="53" width="2.5" height="18" rx="1" fill="rgba(255,248,200,0.4)"/>
      <rect x="55" y="96" width="14" height="89" rx="2" fill="rgba(0,0,0,0.65)" transform="translate(3,2)"/>
      <rect x="55" y="96" width="14" height="89" rx="2" fill="url(#co-tr-armV)" filter="url(#co-tr-ds)"/>
      <rect x="56" y="98" width="1.5" height="85" rx="0.5" fill="rgba(255,248,210,0.5)"/>
      <rect x="61" y="98" width="1"   height="85" rx="0.5" fill="rgba(255,248,210,0.28)"/>
      <rect x="66" y="98" width="1.5" height="85" rx="0.5" fill="rgba(0,0,0,0.45)"/>
      <rect x="56" y="118" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="118.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="56" y="138" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="138.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="56" y="158" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="158.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="52" y="178" width="20" height="7" rx="2" fill="url(#co-tr-armV)" filter="url(#co-tr-ds)"/>
      <rect x="53" y="179" width="18" height="2.5" rx="1" fill="rgba(255,248,200,0.4)"/>
      <circle cx="63" cy="63" r="57" fill="rgba(0,0,0,0.75)" transform="translate(2,5)"/>
      <circle cx="63" cy="63" r="57" fill="url(#co-tr-boss)" filter="url(#co-tr-ds)"/>
      <circle cx="63" cy="63" r="52" fill="none" stroke="rgba(0,0,0,0.55)" stroke-width="2"/>
      <circle cx="63" cy="63" r="50" fill="none" stroke="rgba(255,235,155,0.28)" stroke-width="0.75"/>
      <circle cx="63" cy="63" r="40" fill="none" stroke="rgba(0,0,0,0.45)" stroke-width="1.5"/>
      <circle cx="63" cy="63" r="38.5" fill="none" stroke="rgba(255,235,155,0.22)" stroke-width="0.5"/>
      <polygon points="63,34 84,63 63,92 42,63" fill="none" stroke="rgba(20,12,4,0.7)" stroke-width="2"/>
      <polygon points="63,38 80,63 63,88 46,63" fill="none" stroke="rgba(233,201,122,0.32)" stroke-width="0.75"/>
      <line x1="63" y1="36" x2="63" y2="90" stroke="rgba(20,12,4,0.35)" stroke-width="0.75"/>
      <line x1="36" y1="63" x2="90" y2="63" stroke="rgba(20,12,4,0.35)" stroke-width="0.75"/>
      <circle cx="63" cy="38" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="62" cy="37" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="88" cy="63" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="87" cy="62" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="63" cy="88" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="62" cy="87" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="38" cy="63" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="37" cy="62" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="63" cy="63" r="20" fill="url(#co-tr-gem)" stroke="#9a6f2a" stroke-width="1.5"/>
      <circle cx="63" cy="63" r="18" fill="none" stroke="rgba(233,201,122,0.35)" stroke-width="0.75"/>
      <ellipse cx="57" cy="56" rx="5" ry="3.5" fill="rgba(255,245,210,0.22)" transform="rotate(-25,57,56)"/>
      <circle cx="63" cy="63" r="9"  fill="none" stroke="rgba(154,111,42,0.6)" stroke-width="1"/>
      <circle cx="63" cy="63" r="5"  fill="#c99a45" stroke="rgba(0,0,0,0.5)" stroke-width="0.75"/>
      <circle cx="61.5" cy="61.5" r="2" fill="rgba(255,248,220,0.75)"/>
    </svg>

    <!-- BOTTOM LEFT (mirrored vertically) -->
    <svg class="corner-ornament bl" viewBox="0 0 185 185" overflow="visible">
      <defs>
        <radialGradient id="co-bl-boss" cx="34%" cy="28%" r="68%">
          <stop offset="0%"   stop-color="#fffde8"/><stop offset="14%"  stop-color="#f4d98b"/>
          <stop offset="44%"  stop-color="#c99a45"/><stop offset="72%"  stop-color="#7a5220"/>
          <stop offset="100%" stop-color="#1e1006"/>
        </radialGradient>
        <radialGradient id="co-bl-gem" cx="34%" cy="28%" r="62%">
          <stop offset="0%"   stop-color="#4a2814"/><stop offset="45%"  stop-color="#1a0d04"/>
          <stop offset="100%" stop-color="#070402"/>
        </radialGradient>
        <linearGradient id="co-bl-armH" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#1a0d04"/><stop offset="28%"  stop-color="#c99a45"/>
          <stop offset="50%"  stop-color="#f4d98b"/><stop offset="72%"  stop-color="#c99a45"/>
          <stop offset="100%" stop-color="#1a0d04"/>
        </linearGradient>
        <linearGradient id="co-bl-armV" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%"   stop-color="#1a0d04"/><stop offset="28%"  stop-color="#c99a45"/>
          <stop offset="50%"  stop-color="#f4d98b"/><stop offset="72%"  stop-color="#c99a45"/>
          <stop offset="100%" stop-color="#1a0d04"/>
        </linearGradient>
        <filter id="co-bl-ds"><feDropShadow dx="1" dy="4" stdDeviation="5" flood-color="#000" flood-opacity="0.9"/></filter>
      </defs>
      <rect x="96" y="55" width="89" height="14" rx="2" fill="rgba(0,0,0,0.65)" transform="translate(2,4)"/>
      <rect x="96" y="55" width="89" height="14" rx="2" fill="url(#co-bl-armH)" filter="url(#co-bl-ds)"/>
      <rect x="98" y="56" width="85" height="1.5" rx="0.5" fill="rgba(255,248,210,0.5)"/>
      <rect x="98" y="60" width="85" height="1"   rx="0.5" fill="rgba(255,248,210,0.28)"/>
      <rect x="98" y="66" width="85" height="1.5" rx="0.5" fill="rgba(0,0,0,0.45)"/>
      <rect x="118" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="118.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="138" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="138.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="158" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="158.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="178" y="52" width="7" height="20" rx="2" fill="url(#co-bl-armH)" filter="url(#co-bl-ds)"/>
      <rect x="179" y="53" width="2.5" height="18" rx="1" fill="rgba(255,248,200,0.4)"/>
      <rect x="55" y="96" width="14" height="89" rx="2" fill="rgba(0,0,0,0.65)" transform="translate(3,2)"/>
      <rect x="55" y="96" width="14" height="89" rx="2" fill="url(#co-bl-armV)" filter="url(#co-bl-ds)"/>
      <rect x="56" y="98" width="1.5" height="85" rx="0.5" fill="rgba(255,248,210,0.5)"/>
      <rect x="61" y="98" width="1"   height="85" rx="0.5" fill="rgba(255,248,210,0.28)"/>
      <rect x="66" y="98" width="1.5" height="85" rx="0.5" fill="rgba(0,0,0,0.45)"/>
      <rect x="56" y="118" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="118.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="56" y="138" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="138.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="56" y="158" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="158.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="52" y="178" width="20" height="7" rx="2" fill="url(#co-bl-armV)" filter="url(#co-bl-ds)"/>
      <rect x="53" y="179" width="18" height="2.5" rx="1" fill="rgba(255,248,200,0.4)"/>
      <circle cx="63" cy="63" r="57" fill="rgba(0,0,0,0.75)" transform="translate(2,5)"/>
      <circle cx="63" cy="63" r="57" fill="url(#co-bl-boss)" filter="url(#co-bl-ds)"/>
      <circle cx="63" cy="63" r="52" fill="none" stroke="rgba(0,0,0,0.55)" stroke-width="2"/>
      <circle cx="63" cy="63" r="50" fill="none" stroke="rgba(255,235,155,0.28)" stroke-width="0.75"/>
      <circle cx="63" cy="63" r="40" fill="none" stroke="rgba(0,0,0,0.45)" stroke-width="1.5"/>
      <circle cx="63" cy="63" r="38.5" fill="none" stroke="rgba(255,235,155,0.22)" stroke-width="0.5"/>
      <polygon points="63,34 84,63 63,92 42,63" fill="none" stroke="rgba(20,12,4,0.7)" stroke-width="2"/>
      <polygon points="63,38 80,63 63,88 46,63" fill="none" stroke="rgba(233,201,122,0.32)" stroke-width="0.75"/>
      <line x1="63" y1="36" x2="63" y2="90" stroke="rgba(20,12,4,0.35)" stroke-width="0.75"/>
      <line x1="36" y1="63" x2="90" y2="63" stroke="rgba(20,12,4,0.35)" stroke-width="0.75"/>
      <circle cx="63" cy="38" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="62" cy="37" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="88" cy="63" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="87" cy="62" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="63" cy="88" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="62" cy="87" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="38" cy="63" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="37" cy="62" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="63" cy="63" r="20" fill="url(#co-bl-gem)" stroke="#9a6f2a" stroke-width="1.5"/>
      <circle cx="63" cy="63" r="18" fill="none" stroke="rgba(233,201,122,0.35)" stroke-width="0.75"/>
      <ellipse cx="57" cy="56" rx="5" ry="3.5" fill="rgba(255,245,210,0.22)" transform="rotate(-25,57,56)"/>
      <circle cx="63" cy="63" r="9"  fill="none" stroke="rgba(154,111,42,0.6)" stroke-width="1"/>
      <circle cx="63" cy="63" r="5"  fill="#c99a45" stroke="rgba(0,0,0,0.5)" stroke-width="0.75"/>
      <circle cx="61.5" cy="61.5" r="2" fill="rgba(255,248,220,0.75)"/>
    </svg>

    <!-- BOTTOM RIGHT (mirrored both) -->
    <svg class="corner-ornament br" viewBox="0 0 185 185" overflow="visible">
      <defs>
        <radialGradient id="co-br-boss" cx="34%" cy="28%" r="68%">
          <stop offset="0%"   stop-color="#fffde8"/><stop offset="14%"  stop-color="#f4d98b"/>
          <stop offset="44%"  stop-color="#c99a45"/><stop offset="72%"  stop-color="#7a5220"/>
          <stop offset="100%" stop-color="#1e1006"/>
        </radialGradient>
        <radialGradient id="co-br-gem" cx="34%" cy="28%" r="62%">
          <stop offset="0%"   stop-color="#4a2814"/><stop offset="45%"  stop-color="#1a0d04"/>
          <stop offset="100%" stop-color="#070402"/>
        </radialGradient>
        <linearGradient id="co-br-armH" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"   stop-color="#1a0d04"/><stop offset="28%"  stop-color="#c99a45"/>
          <stop offset="50%"  stop-color="#f4d98b"/><stop offset="72%"  stop-color="#c99a45"/>
          <stop offset="100%" stop-color="#1a0d04"/>
        </linearGradient>
        <linearGradient id="co-br-armV" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%"   stop-color="#1a0d04"/><stop offset="28%"  stop-color="#c99a45"/>
          <stop offset="50%"  stop-color="#f4d98b"/><stop offset="72%"  stop-color="#c99a45"/>
          <stop offset="100%" stop-color="#1a0d04"/>
        </linearGradient>
        <filter id="co-br-ds"><feDropShadow dx="1" dy="4" stdDeviation="5" flood-color="#000" flood-opacity="0.9"/></filter>
      </defs>
      <rect x="96" y="55" width="89" height="14" rx="2" fill="rgba(0,0,0,0.65)" transform="translate(2,4)"/>
      <rect x="96" y="55" width="89" height="14" rx="2" fill="url(#co-br-armH)" filter="url(#co-br-ds)"/>
      <rect x="98" y="56" width="85" height="1.5" rx="0.5" fill="rgba(255,248,210,0.5)"/>
      <rect x="98" y="60" width="85" height="1"   rx="0.5" fill="rgba(255,248,210,0.28)"/>
      <rect x="98" y="66" width="85" height="1.5" rx="0.5" fill="rgba(0,0,0,0.45)"/>
      <rect x="118" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="118.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="138" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="138.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="158" y="56" width="3" height="12" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="158.5" y="57" width="1" height="10" fill="rgba(255,240,180,0.18)"/>
      <rect x="178" y="52" width="7" height="20" rx="2" fill="url(#co-br-armH)" filter="url(#co-br-ds)"/>
      <rect x="179" y="53" width="2.5" height="18" rx="1" fill="rgba(255,248,200,0.4)"/>
      <rect x="55" y="96" width="14" height="89" rx="2" fill="rgba(0,0,0,0.65)" transform="translate(3,2)"/>
      <rect x="55" y="96" width="14" height="89" rx="2" fill="url(#co-br-armV)" filter="url(#co-br-ds)"/>
      <rect x="56" y="98" width="1.5" height="85" rx="0.5" fill="rgba(255,248,210,0.5)"/>
      <rect x="61" y="98" width="1"   height="85" rx="0.5" fill="rgba(255,248,210,0.28)"/>
      <rect x="66" y="98" width="1.5" height="85" rx="0.5" fill="rgba(0,0,0,0.45)"/>
      <rect x="56" y="118" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="118.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="56" y="138" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="138.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="56" y="158" width="12" height="3" rx="1" fill="rgba(0,0,0,0.4)"/>
      <rect x="57" y="158.5" width="10" height="1" fill="rgba(255,240,180,0.18)"/>
      <rect x="52" y="178" width="20" height="7" rx="2" fill="url(#co-br-armV)" filter="url(#co-br-ds)"/>
      <rect x="53" y="179" width="18" height="2.5" rx="1" fill="rgba(255,248,200,0.4)"/>
      <circle cx="63" cy="63" r="57" fill="rgba(0,0,0,0.75)" transform="translate(2,5)"/>
      <circle cx="63" cy="63" r="57" fill="url(#co-br-boss)" filter="url(#co-br-ds)"/>
      <circle cx="63" cy="63" r="52" fill="none" stroke="rgba(0,0,0,0.55)" stroke-width="2"/>
      <circle cx="63" cy="63" r="50" fill="none" stroke="rgba(255,235,155,0.28)" stroke-width="0.75"/>
      <circle cx="63" cy="63" r="40" fill="none" stroke="rgba(0,0,0,0.45)" stroke-width="1.5"/>
      <circle cx="63" cy="63" r="38.5" fill="none" stroke="rgba(255,235,155,0.22)" stroke-width="0.5"/>
      <polygon points="63,34 84,63 63,92 42,63" fill="none" stroke="rgba(20,12,4,0.7)" stroke-width="2"/>
      <polygon points="63,38 80,63 63,88 46,63" fill="none" stroke="rgba(233,201,122,0.32)" stroke-width="0.75"/>
      <line x1="63" y1="36" x2="63" y2="90" stroke="rgba(20,12,4,0.35)" stroke-width="0.75"/>
      <line x1="36" y1="63" x2="90" y2="63" stroke="rgba(20,12,4,0.35)" stroke-width="0.75"/>
      <circle cx="63" cy="38" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="62" cy="37" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="88" cy="63" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="87" cy="62" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="63" cy="88" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="62" cy="87" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="38" cy="63" r="4" fill="#7a5220" stroke="rgba(0,0,0,0.6)" stroke-width="0.5"/>
      <circle cx="37" cy="62" r="1.5" fill="rgba(255,245,200,0.6)"/>
      <circle cx="63" cy="63" r="20" fill="url(#co-br-gem)" stroke="#9a6f2a" stroke-width="1.5"/>
      <circle cx="63" cy="63" r="18" fill="none" stroke="rgba(233,201,122,0.35)" stroke-width="0.75"/>
      <ellipse cx="57" cy="56" rx="5" ry="3.5" fill="rgba(255,245,210,0.22)" transform="rotate(-25,57,56)"/>
      <circle cx="63" cy="63" r="9"  fill="none" stroke="rgba(154,111,42,0.6)" stroke-width="1"/>
      <circle cx="63" cy="63" r="5"  fill="#c99a45" stroke="rgba(0,0,0,0.5)" stroke-width="0.75"/>
      <circle cx="61.5" cy="61.5" r="2" fill="rgba(255,248,220,0.75)"/>
    </svg>

    <!-- Studs -->
    <div class="book-studs-top">
      <div class="stud"></div><div class="stud"></div><div class="stud"></div>
      <div class="stud"></div><div class="stud"></div><div class="stud"></div>
      <div class="stud"></div><div class="stud"></div><div class="stud"></div>
    </div>
    <div class="book-studs-bottom">
      <div class="stud"></div><div class="stud"></div><div class="stud"></div>
      <div class="stud"></div><div class="stud"></div><div class="stud"></div>
      <div class="stud"></div><div class="stud"></div><div class="stud"></div>
    </div>
    <div class="book-studs-right">
      <div class="stud"></div><div class="stud"></div><div class="stud"></div>
      <div class="stud"></div><div class="stud"></div><div class="stud"></div>
      <div class="stud"></div>
    </div>

    <!-- Clasp -->
    <div class="book-clasp"></div>

    <!-- Page area -->
    <div class="page-inner">
      <div class="note-content">
        <!--
          ┌─────────────────────────────────────────────┐
          │  INJECTION POINTS FOR BIGNOTE BOX ADDON     │
          │                                             │
          │  Set innerHTML or textContent of:           │
          │    #note-title  — the note heading          │
          │    #note-body   — the note body (HTML ok)   │
          └─────────────────────────────────────────────┘
        -->
        <h1 class="note-title" id="note-title">%%NOTE_TITLE%%</h1>
        <div class="note-body" id="note-body">
          %%NOTE_BODY%%
        </div>
      </div>
      <div class="page-vignette"></div>
    </div>

  </div><!-- .book -->
</div><!-- .book-shell -->

<script>
/* embers.js — vanilla fire & ember animation for BigNoteBox tome */
(function () {
  'use strict';

  var EMBER_COUNT = 80;

  function createScene() {
    var scene = document.createElement('div');
    scene.className = 'scene';

    ['', 'b', 'c'].forEach(function (cls) {
      var g = document.createElement('div');
      g.className = 'fire-glow' + (cls ? ' ' + cls : '');
      scene.appendChild(g);
    });

    for (var i = 0; i < EMBER_COUNT; i++) {
      var e = document.createElement('div');
      e.className = 'ember';
      var dur   = 18 + Math.random() * 18;
      var delay = -(Math.random() * 22);
      var size  = 2 + Math.random() * 3;
      var dx    = (Math.random() * 120 - 60);
      e.style.cssText = [
        'left:'                 + (Math.random() * 100) + 'vw',
        'animation-duration:'  + dur   + 's',
        'animation-delay:'     + delay + 's',
        'width:'               + size  + 'px',
        'height:'              + size  + 'px',
        '--dx:'                + dx    + 'px',
      ].join(';');
      scene.appendChild(e);
    }

    document.body.insertBefore(scene, document.body.firstChild);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', createScene);
  } else {
    createScene();
  }
})();
</script>
<template id="__bundler_thumbnail">
  <svg viewBox="0 0 120 80" xmlns="http://www.w3.org/2000/svg">
    <rect width="120" height="80" fill="#0e0804"/>
    <rect x="22" y="12" width="76" height="56" rx="3" fill="#2a1508" stroke="#c99a45" stroke-width="1.5"/>
    <rect x="22" y="12" width="14" height="56" rx="2" fill="#1a0d06" stroke="#c99a45" stroke-width="0.75"/>
    <rect x="34" y="22" width="56" height="36" rx="1" fill="#d4a96a" opacity="0.9"/>
    <text x="62" y="38" font-family="serif" font-size="7" fill="#2a1508" text-anchor="middle" font-weight="bold">BigNoteBox</text>
    <text x="62" y="50" font-family="serif" font-size="4" fill="#5a3a1a" text-anchor="middle">— note export —</text>
  </svg>
</template>
</body>
</html>
]=]
    return _cached
end
