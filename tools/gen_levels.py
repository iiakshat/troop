"""Generates the 50 campaign levels: config/levels/level_1.json .. level_50.json.

  python -I tools/gen_levels.py            # writes all 50
  python -I tools/gen_levels.py 7 12       # only levels 7..12

Deterministic: every level has its own seed (1000 + level), so a rerun writes the same
files. Numbers come from config/units.json (unlock levels, enemy stats), never from here.

How a level is built (spec 2026-11-08-troop-v1-design.md, section 3):
- 5 districts x 10 levels; level 10 of each district is a boss level.
- Difficulty is a sawtooth: it ramps through levels 1-9 of a district, peaks at the boss,
  and the next district starts a bit harder than the last one started.
- A level is a run of "beats": a gate row (sometimes two, for operation-order puzzles)
  then a gang wave. Offers (good gates) fill only 1 or 2 lanes; the other lanes hold
  obstacles (pothole, barricade, red gate, car, barrel). One "lucky row" with three offers
  appears in every third level at most.
- A small planning model (the squad maths plus a rough copy of the battle) follows the
  greedy best route and sizes each wave so it costs that route a target share of its
  squad. tests/tune.gd then plays the real sim and fits one scale per level so the share
  of random routes that win follows the target curve; that scale and the best route's
  finish ratio (for the star thresholds) live in config/levels/calibration.json.
- New mechanics arrive gradually (unlock levels in units.json) and each gets a one-time
  icon hint the first time it ever appears.
- Levels 1-3 are hand-written below: gentle, teaching, and a fast power fantasy.
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UNITS = json.loads((ROOT / "config" / "units.json").read_text(encoding="utf-8"))
OUT = ROOT / "config" / "levels"
CAL_PATH = OUT / "calibration.json"
LEVELS = 50

W = UNITS["world"]
ALLIES = UNITS["allies"]
ENEMIES = UNITS["enemies"]
WEAPONS = UNITS["hero_weapons"]
S0 = float(W["scroll_speed"])
FIRE = float(W["fire_range"])
CONTACT = float(W["contact_z"])
# Spec v2 section 12.4: the squad cap grows by district (300 / 1K / 5K / 25K / 100K), so
# gates and gangs scale with it; every count stays an exact integer.
CAPS = [int(c) for c in W["squad_cap"]]
CAP = CAPS[0]
GANG_FIGS = int(W.get("gang_figures", 180))
# Gang size ceilings below were tuned for the v1 squad cap of 150; they grow with the cap.
V1_CAP = 150
RF = UNITS.get("return_fire", {})
# Spec v2.1 section 1 (mirrors LevelSim): return fire opens with a volley, each hit is one
# visible figure, a volley is capped; bosses and lieutenants barrage and shoot a share.
RF_OPEN = float(RF.get("open", 0))
RF_CAP = int(RF.get("volley_cap_pct", 0))
RF_FIGS = max(int(RF.get("figures_shown", W.get("formation_figures", 72))), 1)
BOSS_CFG = UNITS.get("boss", {})
LT_CFG = UNITS.get("lieutenant", {})
LT_BANNER = "LIEUTENANT"


def cap_of(d: int) -> int:
    return CAPS[min(max(d, 1), len(CAPS)) - 1]


def by_district(v, d: int):
    """A per-district config number: v[d - 1] of a list (its last entry past the end), or v."""
    if isinstance(v, list):
        return v[min(max(d, 1), len(v)) - 1] if v else 0
    return v


def volley_loss(total: int, shots: int, figs: int = RF_FIGS, cap_pct: int = RF_CAP) -> int:
    """LevelSim.volley_loss: one figure's troops per hit, a volley at most cap_pct % (one hit)."""
    if total <= 0 or shots <= 0:
        return 0
    per = -(-total // max(figs, 1))
    n = shots * per
    if cap_pct > 0:
        n = min(n, max(per, total * cap_pct // 100))
    return min(n, total)


def share_loss(total: int, pct: int, base: int = -1) -> int:
    """LevelSim.share_loss: pct % of the squad (at least 1), never more than base (-1 = none)."""
    if total <= 0 or pct <= 0:
        return 0
    n = max(total * pct // 100, 1)
    if base >= 0:
        n = min(n, base)
    return min(n, total)


def boss_hp(d: int, dps: float, lieutenant: bool = False) -> int:
    """Spec v2.1 section 1.3: a boss (lieutenant) lasts hp_secs of the expected squad's dps.
    Never scaled by the calibration k x kf (apply_scale skips bosses)."""
    cfg = LT_CFG if lieutenant else BOSS_CFG
    secs = float(by_district(cfg.get("hp_secs", 12), d))
    return nice(max(60 if lieutenant else 150, dps * secs))

DISTRICTS = ["Downtown", "Market", "Docks", "Industrial", "Uptown"]
BOSS_BANNERS = ["KINGPIN", "THE BUTCHER", "DOCK KING", "IRON BARON", "OVERLORD"]
WAVE_BANNERS = ["BIG GANG", "STREET WAR", "RUSH", "AMBUSH", "LAST STAND", "GANG WAR"]
# Spec v2.1 §4.2: 50 unique level names (one per level, no cycle). Not shown on screen (icons and
# numbers only); they name the level in analytics, logs and the design notes.
NAMES = [
    "First Blood", "Rush Hour", "Crossfire", "Night Shift", "The Enforcer",
    "Hostage Run", "Mob Rule", "Downpour", "Gauntlet", "Kingpin",
    "Market Day", "Express Lane", "Stall Ambush", "Lantern Row", "The Collector",
    "Bazaar Rescue", "Stampede", "Monsoon", "Black Market", "The Butcher",
    "Low Tide", "Cargo Rush", "Container Trap", "Fog Horn", "The Quartermaster",
    "Cold Storage", "Dockside Riot", "Squall", "Breakwater", "Dock King",
    "Steel Mill", "Conveyor", "Smoke Stack", "Graveyard Shift", "The Foreman",
    "Boiler Room", "Meltdown", "Acid Rain", "Iron Works", "Iron Baron",
    "Skyline", "Fast Lane", "Penthouse Trap", "Neon Nights", "The Consigliere",
    "Gilded Cage", "Gala Riot", "Thunderhead", "Last Stand", "Overlord",
]

# Spec v2.1 §4.1: every level has an archetype by its slot in the district (1-10). Each one
# changes the wave layout and the street's look, and has its own map-node icon.
ARCHETYPES = {1: "gauntlet", 2: "rush", 3: "ambush", 4: "night", 5: "lieutenant",
              6: "rescue", 7: "horde", 8: "storm", 9: "hard", 10: "boss"}
# Layout knobs per archetype (missing = the gauntlet's standard mix):
#   speed      scroll speed x the world's (level JSON scroll_speed)
#   beats      gate-row + gang beats (else from the planned running time); min_secs = stretch floor
#   combo_p    chance a beat has two gate rows; row_gap / wave_after / next_gap = metres
#              between those rows, from the last row to its gang, and from a gang to the next row
#   mixes      weight x per enemy mix; mul_w = weight of x gates (mul_every: one in every row);
#              loss_k = x each gang's loss target
#   opening    the first gang is on the squad before it reaches the first row (in fire range)
#   pincer_p   chance a second gang follows a gang closely
#   cages      hostage cages (Rescue) instead of that many gangs
#   beats_k    x the number of beats (Horde: few, very large gangs)
#   one_offer  extra chance a row has one offer (more obstacle lanes); guard_p = barricades
#              guarding offers; obstacle_w = weight x per obstacle kind
#   all_kinds  every enemy kind unlocked so far fights in the level (Hard gauntlet)
#   look       per-level street look on top of the district's (config/world_look.json looks)
ARCH = {
    "gauntlet": {},
    "rush": {"speed": 1.2, "beats": 6, "min_secs": 44.0, "combo_p": 0.85, "row_gap": 20, "wave_after": 26,
             "next_gap": 24, "mixes": {"fast": 3.0, "bikers": 3.0, "crowd": 1.5}, "loss_k": 0.85, "look": "rush"},
    "ambush": {"opening": True, "mixes": {"gunline": 3.0, "molotov": 3.0, "snipers": 3.0, "grenadiers": 3.0,
               "warband": 2.5, "bikers": 2.0, "siege": 2.0}, "pincer_p": 0.35, "beats_k": 0.85},
    "night": {"wave_after": 26, "look": "night"},
    "lieutenant": {},
    "rescue": {"cages": 2},
    "horde": {"beats_k": 0.6, "combo_p": 0.7, "wave_after": 44, "next_gap": 40, "mul_w": 3.4, "mul_every": True,
              "loss_k": 1.25,
              "mixes": {"crowd": 3.0, "fast": 2.5, "brutes": 1.5, "riot": 1.5, "bikers": 1.2}},
    "storm": {"one_offer": 0.35, "guard_p": 0.45, "obstacle_w": {"pothole": 2.0, "car": 1.6, "barricade": 1.5},
              "look": "storm"},
    "hard": {"all_kinds": True, "loss_k": 1.15},
    "boss": {},
}
CAR_LEVEL = 9          # cars first show up here (spec v2.1 §4.2: their hint card at L9)
CAGE_GUARDS = ("thug", "knifer", "brute", "riot", "gunman")   # gangs that stand guard over a cage


def archetype(level: int) -> str:
    return ARCHETYPES[index_in_district(level)]


def debut_rank(level: int) -> str:
    """The rank that unlocks at exactly this level ('' if none): its first recruit gate shows here."""
    for r, u in ALLIES.items():
        if r not in ("hero", "constable") and int(u["unlock"]) == level:
            return r
    return ""


def debut_enemy(level: int) -> str:
    for e, u in ENEMIES.items():
        if e != "boss" and int(u["unlock"]) == level:
            return e
    return ""

# Lucky rows (offers in all three lanes): at most one, only in every third level.
LUCKY_EVERY = 3
# Shortest track, in seconds of running (spec: levels last 60-90 s; halts add time).
MIN_SECS = 62.0

# Target share of random routes that win (tests/tune.gd fits a scale to hit it):
# about 70% in levels 1-5 falling to 15-25% in 40-50; sawtooth inside each district.
WIN_START = [0.78, 0.62, 0.50, 0.40, 0.30]
WIN_END = [0.50, 0.42, 0.33, 0.25, 0.18]
WIN_BOSS = [0.45, 0.36, 0.28, 0.22, 0.15]


def district(level: int) -> int:
    return (level - 1) // 10 + 1


def index_in_district(level: int) -> int:
    return (level - 1) % 10 + 1


def is_boss(level: int) -> bool:
    return index_in_district(level) == 10


def target_win(level: int) -> float:
    d = district(level) - 1
    i = index_in_district(level)
    if i == 10:
        return WIN_BOSS[d]
    return WIN_START[d] + (WIN_END[d] - WIN_START[d]) * (i - 1) / 8.0


def target_ratio(level: int) -> float:
    """Share of its peak squad the best route should finish with (-1 = no target: district 1
    is the power fantasy)."""
    d = district(level)
    if d == 1:
        return -1.0
    return [0.0, 0.58, 0.5, 0.45, 0.4][d - 1] - (0.06 if is_boss(level) else 0.0)


# Spec v2 calibration rule 1: upgrades gate progress, gently from mid district 1 and more
# often after that. In these levels (district 2: 1, district 3: 2, district 4: 3, district 5:
# 3) even the best route a tapping player can find loses with zero upgrades, while the no-ad
# pace (tapping or not) wins it; tests/tune.gd keeps it so (it grows the last wave when needed
# and refits the earlier ones). Tried and dropped (2026-11-12): L7-L10, L20, L40, L45, L49 -
# a last wave that beats a capped zero-upgrade squad also beats most random routes (10-15%
# wins instead of 45-54%). District 1's gate is milder: the planned route fails without the
# pace's steps at L5-L10, so a non-upgrader must find another lane.
NEED_UPGRADES = {18, 28, 29, 34, 37, 38, 42, 47, 50}


def need_upgrades(level: int) -> bool:
    return level in NEED_UPGRADES


def difficulty(level: int) -> float:
    """0..~1.1, sawtooth: ramps inside a district, each district starts harder."""
    d = district(level)
    i = index_in_district(level)
    return 0.16 * (d - 1) + 0.055 * (i - 1) + (0.08 if i == 10 else 0.0)


def unlocked(table: dict, level: int) -> list[str]:
    return [k for k, v in table.items() if int(v.get("unlock", 1)) <= level]


def nice(n: float) -> int:
    """Friendly gate numbers: exact below 13, even to 40, multiples of 5 to 1,000, then
    two or three leading digits (1,250 / 12,500 / 125,000)."""
    n = max(1, int(round(n)))
    if n <= 12:
        return n
    if n <= 40:
        return int(round(n / 2.0)) * 2
    if n <= 1000:
        return int(round(n / 5.0)) * 5
    step = 50 if n <= 10000 else (500 if n <= 100000 else 5000)
    return int(round(n / float(step))) * step


# ------------------------------------------------------------------ squad (mirrors Squad)

ORDER = ["constable", "sergeant", "inspector", "swat", "sniper", "commando", "hero"]


class Sq:
    def __init__(self, d: int = 1):
        self.c = {r: 0 for r in ORDER}
        self.c["hero"] = 1
        self.d = d              # district: the cap, gang ceilings and return fire follow it
        self.cap = cap_of(d)
        self.weapon = ""

    def copy(self) -> "Sq":
        s = Sq(self.d)
        s.cap = self.cap
        s.c = dict(self.c)
        s.weapon = self.weapon
        return s

    def total(self) -> int:
        return sum(self.c.values())

    def alive(self) -> bool:
        return self.c["hero"] > 0

    def add(self, rank: str, n: int) -> int:
        n = max(n, 0)
        if self.cap > 0:
            n = min(n, max(self.cap - self.total(), 0))
        self.c[rank] = self.c.get(rank, 0) + n
        return n

    def multiply(self, k: int) -> None:
        if k <= 1:
            return
        for r in self.c:
            if r != "hero":
                self.c[r] *= k
        self.c["constable"] += self.c["hero"] * (k - 1)
        if self.cap > 0 and self.total() > self.cap:
            self.lose(self.total() - self.cap)

    def lose(self, n: int) -> int:
        left = max(n, 0)
        for r in ORDER:
            if left <= 0:
                break
            take = min(left, self.c.get(r, 0))
            self.c[r] -= take
            left -= take
        return max(n, 0) - left

    def pct(self, p: int) -> None:
        amount = self.total() * abs(p) // 100
        if p >= 0:
            self.add("constable", amount)
        else:
            self.lose(amount)

    def dps(self, armour: int, hp: float, enemies: int, which: str = "all") -> float:
        s = 0.0
        for r, n in self.c.items():
            if n <= 0 or r not in ALLIES:
                continue
            sniper = ALLIES[r].get("target", "") == "toughest"
            if (which == "main" and sniper) or (which == "snipe" and not sniper):
                continue
            s += n * hit_value(ALLIES[r], armour, hp, enemies)
        if which != "snipe" and self.weapon and self.alive():
            s += hit_value(WEAPONS[self.weapon], armour, hp, enemies)
        return s

    def pierce_dps(self, hp: float, enemies: int, which: str = "all") -> float:
        s = 0.0
        for r, n in self.c.items():
            if n <= 0 or r not in ALLIES or not ALLIES[r].get("pierce", False):
                continue
            sniper = ALLIES[r].get("target", "") == "toughest"
            if (which == "main" and sniper) or (which == "snipe" and not sniper):
                continue
            s += n * hit_value(ALLIES[r], 0, hp, enemies)
        return s

    def has_snipers(self) -> bool:
        return any(n > 0 and ALLIES.get(r, {}).get("target", "") == "toughest" for r, n in self.c.items())

    def power(self) -> float:
        """Constable-equivalents of damage against a plain crowd."""
        return self.dps(0, 1.0, 1 << 30) / float(ALLIES["constable"]["rate"])


def hit_value(unit: dict, armour: int, hp: float, enemies: int, nominal: bool = False) -> float:
    dmg = float(unit.get("dmg", 1))
    if not unit.get("pierce", False):
        dmg = dmg / float(1 + max(armour, 0))
    if not nominal and unit.get("one_per_shot", False):
        dmg = min(dmg, max(hp, 0.0))
    multi = float(unit.get("multi", 1))
    if multi > 1.0 and hp > dmg:
        multi = 1.0
    hits = min(multi * float(unit.get("splash", 1)), float(max(enemies, 1)))
    return dmg * float(unit.get("rate", 1.0)) * max(hits, 1.0)


def enemy_def(grp: dict) -> dict:
    d = dict(ENEMIES[grp["enemy"]])
    for k, v in grp.items():
        if k not in ("enemy", "n", "gap") and k in d:
            d[k] = v
    return d


# ------------------------------------------------------------------ rough battle model

def fight(sq: Sq, groups: list[dict], dt: float = 0.05, fire_k: float = 1.0) -> bool:
    """Plays one wave against `sq` (changed in place) with a simplified copy of LevelSim's
    battle rules: no gates, no powers, no dodging (every telegraphed attack lands, capped).
    `fire_k` is the level's enemy fire intensity (LevelSim.fire_k: return-fire shots x fire_k,
    specials attack fire_k x as often; bosses and the level's first gang keep their numbers).
    The plan sizes waves at 1; calibration.json fire_k is applied on top, like k. Returns True
    if the hero lives."""
    hs = []
    x0 = 0.0
    for g in groups:
        d = enemy_def(g)
        v = float(d["speed"])
        stop = float(d.get("stop_at", 0.0))
        x0 = max(x0, (FIRE + 1.0 - stop) * S0 / (S0 + v) - float(g.get("gap", 0.0)))
    for g in groups:
        d = enemy_def(g)
        v = float(d["speed"])
        stop = float(d.get("stop_at", 0.0))
        n = int(g["n"])
        # Spec v2.1 section 1.2-1.3: specials telegraph from attack.start_m; bosses shoot a share
        # and barrage from the halt (LevelSim._gunfire / _boss_fire).
        atk = d.get("attack", {})
        boss = bool(d.get("boss", False))
        attack = str(atk.get("kind", "")) if atk else ("gun" if boss else "")
        every = float(d.get("throw_every", d.get("shoot_every", 0.0)))
        first = float(d.get("first_shot", every))
        if not boss and every > 0 and fire_k > 0:
            every /= fire_k
            first /= fire_k
        rf = d.get("return_fire", {})
        rf_on = sq.d >= int(rf.get("from_district", RF.get("from_district", 2)))
        hs.append({"n": n, "start": n, "hp": float(d["hp"]), "armour": int(d["armour"]),
                   "power": int(d["power"]), "v": v, "stop": stop, "cols": int(d.get("cols", 9)),
                   # a huge gang stands in GANG_FIGS figures of `per` people (LevelSim)
                   "per": max(1, (n + GANG_FIGS - 1) // GANG_FIGS),
                   "gap": float(d.get("row_gap", 0.95)), "boss": boss,
                   "lt": boss and bool(g.get("lieutenant", False)), "bt": -1.0,
                   "z": -stop - (x0 + float(g.get("gap", 0.0))) * (S0 + v) / S0,
                   "shield": float(d.get("shield", 0.0)) * n, "acc": 0.0, "st": max(every - first, 0.0), "mt": 0.0,
                   "stopped": False, "melee": False, "attack": attack, "every": every,
                   "hit": int(d.get("burn", d.get("shot_dmg", 1))),
                   "cap": int(atk.get("cap_pct", 0)), "warn": float(atk.get("warn_s", 1.0)),
                   "range": float(atk.get("start_m", d.get("shoot_range", 0.0))) if atk else float(d.get("shoot_range", 0.0)),
                   # return fire (spec v2.1 section 1.1)
                   "rf_rate": float(rf.get("rate", 0.0)) * fire_k if rf_on else 0.0,
                   "rf_share": int(rf.get("share", 0)),
                   "rf_max": int(by_district(RF.get("max_shooters", 1 << 30), sq.d)), "rf_open": False,
                   "rf_range": float(rf.get("range", RF.get("range", 50.0))), "rf_acc": 0.0})
    pending: list[list] = []  # telegraphed attacks in the air: [land time, base, pct]
    had = sq.total() > 1      # return fire never takes a hero who never had followers

    def row_size(h):
        return max(h["cols"], 1) * h["per"]

    def front(h):
        return h["z"] - ((h["start"] - h["n"]) // row_size(h)) * h["gap"]

    def damage(h, dmg, pierce):
        if h["shield"] > 0:
            blocked = min(h["shield"], max(dmg - pierce, 0.0))
            h["shield"] -= blocked
            dmg -= blocked
        h["acc"] += dmg
        k = min(int(h["acc"] // h["hp"]), h["n"])
        if k > 0:
            h["acc"] -= k * h["hp"]
            h["n"] -= k

    t = 0.0
    while t < 120.0 and sq.alive():
        hs = [h for h in hs if h["n"] > 0]
        if not hs:
            break
        t += dt
        speed = 0.0 if any(h["boss"] and front(h) >= -float(W["boss_halt"]) for h in hs) else S0
        for h in hs:
            if h["melee"]:
                h["z"] = CONTACT + ((h["start"] - h["n"]) // row_size(h)) * h["gap"]
                continue
            if h["stopped"]:
                # The rows behind walk up to the stop line as the front falls (LevelSim._move).
                line = -h["stop"] + ((h["start"] - h["n"]) // row_size(h)) * h["gap"]
                if h["z"] < line:
                    h["z"] = min(line, h["z"] + (speed + h["v"]) * dt)
                continue
            h["z"] += (speed + h["v"]) * dt
            if h["stop"] > 0 and front(h) >= -h["stop"]:
                h["z"] = -h["stop"] + ((h["start"] - h["n"]) // row_size(h)) * h["gap"]
                h["stopped"] = True
        in_range = [h for h in hs if front(h) >= -FIRE and h["n"] > 0]
        which = "all"
        if in_range and sq.has_snipers():
            tough = max(in_range, key=lambda h: (1e9 if h["boss"] else h["hp"] * (1 + h["armour"]), front(h)))
            which = "main"
            damage(tough, sq.dps(tough["armour"], tough["hp"], tough["n"], "snipe") * dt,
                   sq.pierce_dps(tough["hp"], tough["n"], "snipe") * dt)
        in_range = [h for h in in_range if h["n"] > 0]
        if in_range:
            h = max(in_range, key=front)
            damage(h, sq.dps(h["armour"], h["hp"], h["n"], which) * dt, sq.pierce_dps(h["hp"], h["n"], which) * dt)
        for h in hs:
            # Ranged attacks (LevelSim._gunfire, _boss_fire). The planned squad never dodges or
            # shields, so every telegraphed attack lands (capped at its share of the squad).
            if h["n"] <= 0 or not h["attack"] or h["melee"]:
                continue
            cfg = LT_CFG if h["lt"] else BOSS_CFG
            if h["every"] > 0 and (h["stopped"] or (h["range"] > 0 and front(h) >= -h["range"])):
                h["st"] += dt
                while h["st"] >= h["every"]:
                    h["st"] -= h["every"]
                    if h["boss"]:
                        n = share_loss(sq.total(), int(cfg.get("gun_pct", 0)))
                        sq.lose(n if had else min(n, sq.total() - 1))
                    else:
                        pending.append([t + h["warn"], h["n"] * h["hit"], h["cap"]])
            bevery = float(cfg.get("barrage_every", 0.0))
            if h["boss"] and bevery > 0 and front(h) >= -float(W["boss_halt"]):
                if h["bt"] < 0:
                    h["bt"] = max(bevery - float(cfg.get("barrage_first", 1.0)), 0.0)
                h["bt"] += dt
                while h["bt"] >= bevery:
                    h["bt"] -= bevery
                    pending.append([t + float(cfg.get("warn_s", 1.0)), -1, int(by_district(cfg.get("barrage_pct", 0), sq.d))])
        for h in hs:
            # Return fire (LevelSim._return_fire): an opening volley on entering rf_range, then
            # shooters = share % of the gang (rounded up, at most rf_max) x rf_rate shots/s;
            # each hit one figure's troops, a volley capped (volley_loss).
            if h["n"] <= 0 or h["rf_rate"] <= 0 or h["melee"] or front(h) < -h["rf_range"]:
                continue
            if not h["rf_open"]:
                h["rf_open"] = True
                h["rf_acc"] += RF_OPEN * max(fire_k, 1.0)
            h["rf_acc"] += min((h["n"] * h["rf_share"] + 99) // 100, h["rf_max"]) * h["rf_rate"] * dt
            shots = int(math.floor(h["rf_acc"]))
            if shots > 0:
                h["rf_acc"] -= shots
                n = volley_loss(sq.total(), shots)
                sq.lose(n if had else min(n, sq.total() - 1))
        for p in [p for p in pending if p[0] <= t + 1e-9]:
            pending.remove(p)
            sq.lose(share_loss(sq.total(), p[2], p[1]))
        for h in hs:
            if h["n"] <= 0:
                continue
            if not h["melee"]:
                if front(h) < CONTACT:
                    continue
                h["melee"] = True
                h["mt"] = 0.0
            h["mt"] -= dt
            if h["mt"] > 0:
                continue
            h["mt"] = float(W["melee_tick"])
            row = min(row_size(h), h["n"])
            sq.lose(row * h["power"])
            if not h["boss"]:
                h["n"] -= row
    return sq.alive()


# ------------------------------------------------------------------ waves

# Enemy mixes. The first group is the screen: a melee crowd that soaks fire for a few
# seconds while the core (the rest) does the damage from behind it. A crowd alone can only
# hurt a squad that kills slower than the crowd arrives, so later waves rely on ranged and
# armoured cores. Entries: (enemy, relative count, gap in metres behind the first group).
MIXES = {
    "crowd":      [("thug", 10.0, 0)],
    "fast":       [("thug", 1.0, 0), ("knifer", 10.0, 8)],
    "gunline":    [("thug", 1.0, 0), ("gunman", 1.0, 10)],
    "brutes":     [("thug", 1.0, 0), ("brute", 1.0, 6)],
    "bikers":     [("biker", 1.0, 0)],
    "riot":       [("thug", 1.0, 0), ("riot", 1.0, 6)],
    "molotov":    [("thug", 1.0, 0), ("molotov", 1.0, 10)],
    "snipers":    [("knifer", 1.0, 0), ("sniper_foe", 1.0, 14)],
    "grenadiers": [("thug", 1.0, 0), ("grenadier", 1.0, 10)],
    "siege":      [("riot", 1.0, 0), ("brute", 1.0, 8), ("gunman", 1.2, 16)],
    "warband":    [("knifer", 1.0, 0), ("biker", 1.0, 8), ("molotov", 0.6, 16)],
}

MIN_COUNT = {"thug": 6, "knifer": 6, "gunman": 3, "brute": 2, "biker": 3, "riot": 5,
             "molotov": 2, "sniper_foe": 2, "grenadier": 2, "boss": 1}
# Gangs can be big (the view draws at most gang_figures bodies per gang and the number tells
# the rest); late squads with strong ranks need big ranged/armoured cores to feel it. These
# were tuned for a squad cap of 150 and grow with the district's cap (max_count).
MAX_COUNT = {"thug": 600, "knifer": 500, "gunman": 400, "brute": 240, "biker": 400, "riot": 600,
             "molotov": 120, "sniper_foe": 90, "grenadier": 200, "boss": 1}


def mix_ok(name: str, level: int) -> bool:
    return all(int(ENEMIES[e]["unlock"]) <= level for e, _, _ in MIXES[name])


def max_count(enemy: str, d: int) -> int:
    """The gang size ceiling in district d: MAX_COUNT grows with the squad cap (spec v2 12.4)."""
    if enemy == "boss":
        return 1
    return MAX_COUNT.get(enemy, 9999) * cap_of(d) // V1_CAP


def screen_size(sq: Sq, enemy: str, secs: float) -> int:
    """How many of `enemy` the squad needs `secs` seconds of fire to cut down."""
    d = ENEMIES[enemy]
    dps = max(sq.dps(int(d["armour"]), float(d["hp"]), 1 << 30), 1.0)
    n = dps * secs / (float(d["hp"]) + float(d.get("shield", 0.0)))
    return max(MIN_COUNT[enemy], min(max_count(enemy, sq.d), int(round(n))))


def wave_groups(mix: list, s: float, screen: int, dist: int = 1) -> list[dict]:
    out = []
    single = len(mix) == 1
    for n, (e, w, gap) in enumerate(mix):
        if n == 0 and not single:
            count = screen
        else:
            count = max(MIN_COUNT.get(e, 1), min(max_count(e, dist), int(round(s * w))))
        g = {"enemy": e, "n": count}
        if gap:
            g["gap"] = gap
        out.append(g)
    return out


def size_wave(sq: Sq, mix: list, loss: float, screen_secs: float) -> tuple[list[dict], Sq]:
    """Scales `mix` so the planned squad loses about `loss` of its troops (or as close as
    the count caps allow). Returns the groups and the squad after the fight."""
    t0 = sq.total()
    want = max(1, int(round(t0 * loss)))
    small = t0 < 12  # a tiny squad can't spare anyone: aim for no losses, with a margin
    if small:
        want = 1
    screen = screen_size(sq, mix[0][0], screen_secs)

    def cost(s: float) -> tuple[bool, int]:
        s2 = sq.copy()
        fight(s2, wave_groups(mix, s, screen, sq.d))
        return s2.alive(), t0 - s2.total()

    top = max(max_count(e, sq.d) / max(w, 0.01) for e, w, _ in (mix if len(mix) == 1 else mix[1:]))
    lo, hi = 0.0, top
    alive, lost = cost(hi)
    if alive and lost < want:
        lo = hi  # even the biggest wave falls short: use it
    else:
        for _ in range(16):
            mid = (lo + hi) / 2.0
            alive, lost = cost(mid)
            if alive and lost < want:
                lo = mid
            else:
                hi = mid
    groups = wave_groups(mix, lo * (0.7 if small else 1.0), screen, sq.d)
    after = sq.copy()
    fight(after, groups)
    return groups, after


# ------------------------------------------------------------------ gates

def red_gate(rng: random.Random, sq: Sq, lane: int, level: int, early: bool = False) -> dict:
    """A red -N (or -%) gate that can be shot up past zero."""
    t = min(sq.total(), 6) if early else sq.total()
    dps = max(sq.dps(0, 1000.0, 1), 3.0)
    if level >= 6 and not early and rng.random() < 0.6:
        v = -rng.choice([30, 40, 50])
        top = rng.choice([20, 30, 40])
        inc = 10
        steps = (top - v) // inc
        return {"lane": lane, "op": "pct", "v": v, "inc": inc, "step": round(2.6 * dps / steps, 1), "max": top}
    n = nice(max(3, t * rng.uniform(0.3, 0.55)))
    top = nice(max(4, n * rng.uniform(0.8, 1.4)))
    inc = max(1, int(round((n + top) / 24.0)))
    steps = max(1, (n + top) // inc)
    return {"lane": lane, "op": "num", "v": -n, "step": round(2.6 * dps / steps, 1), "max": top, "inc": inc}


def lane_obstacle(rng: random.Random, sq: Sq, lane: int, at: float, level: int, early: bool = False,
                  ctx: dict | None = None) -> dict | None:
    """An obstacle event for a lane with no offer (None = use a red gate instead). `early`
    rows (the first beats, when a sloppy squad is still tiny) hit softly. ctx: the archetype's
    obstacle weights (Storm) and the car's debut (its first level always shows one)."""
    ctx = ctx or {}
    t = min(sq.total(), 6) if early else sq.total()
    dps = max(sq.dps(0, 1000.0, 1), 3.0)
    pool = [("red", 3.0)]
    if level >= 2:
        pool.append(("pothole", 2.0))
    if level >= 3:
        pool.append(("barrel", 1.0))
    if level >= 4:
        pool.append(("barricade", 2.0))
    if level >= CAR_LEVEL:
        pool.append(("car", 1.0))
    ow = ctx.get("obstacle_w", {})
    pool = [(k, w * ow.get(k, 1.0)) for k, w in pool]
    kind = rng.choices([k for k, _ in pool], [w for _, w in pool])[0]
    if ctx.get("car_due") and not early:
        kind = "car"
        ctx["car_due"] = False
    if kind == "red":
        return None
    ev = {"at": at, "type": "obstacle", "kind": kind, "lane": lane}
    if kind == "pothole":
        if level >= 6 and not early and rng.random() < 0.65:
            ev["fall_pct"] = rng.choice([20, 25, 30, 35])
        else:
            ev["fall"] = nice(max(2, t * rng.uniform(0.15, 0.3)))
    elif kind == "barricade":
        ev["hp"] = nice(max(6, dps * rng.uniform(1.6, 2.6)))
        if level >= 6 and not early:
            ev["dmg_pct"] = rng.choice([15, 20, 25])
        else:
            ev["dmg"] = nice(max(3, t * rng.uniform(0.15, 0.25)))
    elif kind == "car":
        ev["hp"] = nice(max(15, dps * rng.uniform(2.5, 3.5)))
        if level >= 6 and not early:
            ev["dmg_pct"] = rng.choice([20, 25, 30])
        else:
            ev["dmg"] = nice(max(4, t * rng.uniform(0.2, 0.3)))
    elif kind == "barrel":
        ev["hp"] = nice(max(4, dps * 0.8))
        ev["dmg"] = nice(max(2, t * 0.1))
        ev["radius"] = 8
        ev["kill"] = nice(max(12, t * 0.6))
    return ev


# Spec v2 section 12.4: bigger gates as the cap grows. Growth offers size themselves on the
# squad, but never on less than GROW_FLOOR x the district's cap, so a fresh squad in a late
# district gets a real kick (+350 in district 5, not +7). Multipliers reach x5: the highest
# k a district offers, and the share of rows where the big one shows up.
GROW_FLOOR = 0.01
MUL_TOP = [3, 3, 4, 5, 5]
MUL_BIG_P = [0.35, 0.35, 0.45, 0.5, 0.55]


def grow_base(sq: Sq) -> int:
    return max(sq.total(), int(cap_of(sq.d) * GROW_FLOOR))


def offer(rng: random.Random, kind: str, sq: Sq, lane: int, level: int, ctx: dict) -> dict:
    t = sq.total()
    b = grow_base(sq)
    if kind == "add":
        return {"lane": lane, "op": "num", "v": nice(max(3, b * rng.uniform(0.35, 0.85) + rng.randint(3, 8)))}
    if kind == "mul":
        top = MUL_TOP[sq.d - 1]
        # District 1-2 keep v1's rule (x3 only while the squad is small); later districts
        # offer x3..x5 while the squad is below a fifth of the cap.
        small = t <= 30 if sq.d <= 2 else t * 5 <= sq.cap
        k = 2
        if level >= 2 and small and rng.random() < MUL_BIG_P[sq.d - 1]:
            k = 3 if top == 3 else rng.randint(3, top)  # (districts 1-2 draw as in v1)
        return {"lane": lane, "op": "mul", "k": k}
    if kind == "recruit":
        ranks = [r for r in unlocked(ALLIES, level) if r not in ("hero", "constable")]
        ranks.sort(key=lambda r: int(ALLIES[r]["unlock"]))
        weights = [1.0 + 2.0 * i for i in range(len(ranks))]  # newer ranks more often
        rank = rng.choices(ranks, weights)[0]
        debut = bool(ctx.get("debut_rank")) and not ctx.get("debut_done")
        if debut:
            rank = ctx["debut_rank"]   # its unlock level: the new rank's first gate (and hint card)
            ctx["debut_done"] = True
        value = sq_value(rank)
        n = max(2, int(round((b * rng.uniform(0.25, 0.45) + 4) / value)))
        if debut:
            # A generous first meeting: the new rank is the row's best pick, so players take it.
            n = max(3, int(round((b * 0.7 + 9) / value)))
        return {"lane": lane, "op": "recruit", "unit": rank, "n": nice(n)}
    if kind == "pct":
        return {"lane": lane, "op": "pct", "v": rng.choice([30, 40, 50, 60])}
    if kind == "weapon":
        wid = "smg" if level >= 12 and rng.random() < 0.6 else "pistol"
        return {"lane": lane, "op": "weapon", "id": wid}
    if kind == "power":
        pid = "bomb" if level >= 6 and rng.random() < 0.5 else "shield"
        return {"lane": lane, "op": "power", "id": pid, "n": 1}
    if kind == "foe_strip":
        return {"lane": lane, "op": "foe_strip"}
    if kind == "foe_div":
        return {"lane": lane, "op": "foe_div", "k": 2}
    if kind == "turncoat":
        n = nice(max(6, b * rng.uniform(0.3, 0.6)))
        if n >= 10000:
            n = int(round(n / 1000.0)) * 1000   # "34K", not "33.5K": the sign and its icon fit a lane
        return {"lane": lane, "op": "turncoat", "n": n}
    raise ValueError(kind)


def sq_value(rank: str) -> float:
    """Nominal value line (Squad.value_vs_constable with defaults)."""
    base = hit_value(ALLIES["constable"], 0, 1.0, 1 << 30, True)
    return hit_value(ALLIES[rank], 0, 1.0, 1 << 30, True) / base


def apply_gate(sq: Sq, g: dict) -> None:
    op = g["op"]
    if op == "num":
        if g["v"] >= 0:
            sq.add("constable", g["v"])
        else:
            sq.lose(-g["v"])
    elif op == "mul":
        sq.multiply(g["k"])
    elif op == "recruit":
        sq.add(g["unit"], g["n"])
    elif op == "pct":
        sq.pct(g["v"])
    elif op == "weapon":
        sq.weapon = g["id"]


GROWTH = ("add", "mul", "recruit", "pct")


def offer_kinds(rng: random.Random, level: int, n: int, ctx: dict) -> list[str]:
    if ctx.get("debut_rank") and not ctx.get("debut_done"):
        # The level a rank unlocks: its recruit gate is in the first row.
        kinds = ["recruit"]
        while len(kinds) < n:
            kinds.append("mul" if "mul" not in kinds and rng.random() < 0.5 else "add")
        return kinds
    pool = [("add", 3.0), ("mul", float(ctx.get("mul_w", 2.2)))]
    if any(int(ALLIES[r]["unlock"]) <= level for r in ALLIES if r not in ("hero", "constable")):
        pool.append(("recruit", 2.4 + 0.04 * level))
    if level >= 11:
        pool.append(("pct", 1.0))
    if level >= 5 and not ctx.get("weapon_done"):
        pool.append(("weapon", 0.8))
    if level >= 3:
        pool.append(("power", 0.6))
    if level >= 5 and ctx.get("next_armour"):
        pool.append(("foe_strip", 1.5))
    if level >= 8:
        pool.append(("foe_div", 0.7))
    if level >= 11:
        pool.append(("turncoat", 0.7))
    kinds: list[str] = []
    # At least one growth offer in every row (Horde: a x gate in every row).
    first = rng.choices([k for k, _ in pool if k in GROWTH], [w for k, w in pool if k in GROWTH])[0]
    if ctx.get("mul_every"):
        first = "mul"
    kinds.append(first)
    while len(kinds) < n:
        k = rng.choices([k for k, _ in pool], [w for _, w in pool])[0]
        if k in kinds and k not in ("add", "recruit"):
            continue
        kinds.append(k)
    return kinds


def best_choice(sq: Sq, gates: list[dict]) -> dict | None:
    """The planning model's pick: the growth gate that leaves the most firepower."""
    best, best_v = None, -1.0
    for g in gates:
        if g["op"] not in ("num", "mul", "recruit", "pct") or (g["op"] in ("num", "pct") and g.get("v", 0) < 0):
            continue
        s2 = sq.copy()
        apply_gate(s2, g)
        v = s2.power()
        if v > best_v:
            best, best_v = g, v
    if best is None:
        for g in gates:
            if g["op"] in ("weapon", "power"):
                return g
    return best


# ------------------------------------------------------------------ calibration

def load_calibration() -> dict:
    if CAL_PATH.exists():
        return json.loads(CAL_PATH.read_text(encoding="utf-8"))
    return {}


def scaled(n: int, k: float, minimum: int) -> int:
    return max(minimum, int(math.floor(n * k + 0.5)))


def apply_scale(events: list[dict], k: float, kf: float = 1.0) -> None:
    """Every gang's size and barrel blast x k; the last wave x kf more (same rounding as
    tests/tune.gd). Bosses and lieutenants keep their HP: it is designed in seconds of the
    expected squad's fire (boss_hp, apply_boss_hp), never scaled (spec v2.1 section 1.3)."""
    if abs(k - 1.0) > 1e-9:
        for e in events:
            if e["type"] == "obstacle" and e.get("kind") == "barrel" and "kill" in e:
                e["kill"] = scaled(int(e["kill"]), k, 5)
            elif e["type"] == "cage":
                # A cage's guards are a gang like the others (tests/tune.gd scaled_level scales
                # them the same way).
                e["guards"]["n"] = scaled(int(e["guards"]["n"]), k, 1)
    waves = [e for e in events if e["type"] == "wave"]
    for e in waves:
        if e.get("fixed"):
            continue  # an opening gang sized by hand (levels 1-3, OPENING)
        m = k * (kf if e is waves[-1] else 1.0)
        if abs(m - 1.0) < 1e-9:
            continue
        for g in e["groups"]:
            if g["enemy"] != "boss":
                g["n"] = scaled(int(g["n"]), m, 1)


def apply_boss_hp(events: list[dict], level: int, cal: dict) -> None:
    """Spec v2.1 section 1.3: with a calibrated boss_dps (Autopilot.boss_dps: the squad's dps
    against him when he halts the street, on the stored route at the pace), every boss and
    lieutenant gets hp_secs of it."""
    dps = float(cal.get("boss_dps", 0.0))
    if dps <= 0:
        return
    for e in events:
        if e["type"] == "wave":
            for g in e["groups"]:
                if g["enemy"] == "boss":
                    g["hp"] = boss_hp(district(level), dps, bool(g.get("lieutenant", False)))


def lieutenant_wave(level: int, d: int, sq: Sq | None = None, at: int = 0) -> dict:
    """Spec v2.1 section 1.3: the mini-boss wave of slot 5 (L5, 15, 25, 35, 45), the last wave
    of its level. A boss group with "lieutenant": true (units.json lieutenant numbers: halt,
    gun, `lt_barrage`; drawn 2.4x a thug, smaller bar, no liberation), arriving `at`.

    With `sq` (the planned squad before this wave, changed in place to the squad after the
    crew) a thug crew walks in front of him, sized like a boss crew, and his HP is
    lieutenant.hp_secs of the planned squad's fire after it. Without `sq` he comes alone with
    a district-sized estimate. build() replaces the HP with hp_secs x the calibrated boss_dps
    when calibration.json has one; it is never scaled by k x kf."""
    groups: list[dict] = []
    if sq is not None:
        crew, after = size_wave(sq, MIXES["crowd"], 0.08 + 0.06 * difficulty(level), 1.0 + difficulty(level))
        groups = crew
        sq.c = after.c
    else:
        after = Sq(d)
        after.add("constable", cap_of(d) * 3 // 10)
    dps = max(after.dps(int(ENEMIES["boss"]["armour"]), float(ENEMIES["boss"]["hp"]), 1), 5.0)
    lt = {"enemy": "boss", "lieutenant": True, "n": 1, "hp": boss_hp(d, dps, True)}
    if groups:
        lt["gap"] = 18
    if cap_of(d) > 1000:
        lt["power"] = nice(int(ENEMIES["boss"]["power"]) * cap_of(d) / 1000.0)
    return {"at": at, "type": "wave", "label": LT_BANNER, "groups": groups + [lt]}


def star_thresholds(level: int, cal: dict) -> dict:
    """3 stars = finish close to the best route's share of its peak; 2 stars = about half."""
    best = cal.get("best_ratio")
    if best is None:
        base = [60, 55, 50, 45, 42][district(level) - 1]
        return {"star2": base // 2, "star3": base}
    pct = int(round(best * 100))
    star3 = max(20, min(90, int(pct * 0.85)))
    star2 = max(10, min(star3 - 10, int(pct * 0.45)))
    return {"star2": star2, "star3": star3}


# ------------------------------------------------------------------ hints

HINTS = {  # mechanic -> (hint id, icon, power)
    "red_gate": ("red_gate", "aim", None),
    "pothole": ("pothole", "pothole", None),
    "gunman": ("shield", "shield", "shield"),
    "barrel": ("barrel", "barrel", None),
    "sergeant": ("sergeant", "sergeant", None),
    "barricade": ("barricade", "barricade", None),
    "brute": ("armour", "armour", None),
    "foe_strip": ("no_armour", "armour_break", None),
    "bomb": ("bomb", "bomb", "bomb"),
    "inspector": ("inspector", "inspector", None),
    "riot": ("riot", "riot", None),
    "foe_div": ("gang_split", "gang_split", None),
    "molotov": ("molotov", "molotov", None),
    "turncoat": ("turncoat", "turncoat", None),
    "boss": ("boss", "boss", None),
    "smg": ("smg", "smg", None),
    "swat": ("swat", "swat", None),
    "sniper_foe": ("sniper_foe", "sniper_foe", None),
    "sniper": ("sniper", "sniper", None),
    "grenadier": ("grenadier", "grenadier", None),
    "commando": ("commando", "commando", None),
    "car": ("car", "police_car", None),
    "return_fire": ("return_fire", "thug", None),  # spec v2.1 §1.1: L11, gang ▸ bullet ▸ squad -
    "lieutenant": ("lieutenant", "boss", None),    # spec v2.1 §1.3: L5's mini-boss (his own card)
}


def fires_back_by_district(enemy: str, level: int) -> bool:
    """True when `enemy` fires back in `level` under the district-wide return-fire rule (gangs
    from return_fire.from_district on). An enemy with its own from_district (the gunmen, from
    L3) is left out: its first appearance already teaches the shield."""
    rf = ENEMIES.get(enemy, {}).get("return_fire")
    return bool(rf) and "from_district" not in rf and district(level) >= int(RF.get("from_district", 2))


def mechanics_of(ev: dict, level: int = 0) -> list[tuple[str, float]]:
    """(mechanic, distance at which its hint should show) for one event of `level`."""
    out = []
    at = float(ev["at"])
    if ev["type"] == "gates":
        for g in ev["gates"]:
            op = g["op"]
            if op in ("num", "pct") and g.get("v", 0) < 0 and g.get("step"):
                out.append(("red_gate", at - 28))
            elif op == "recruit":
                out.append((g["unit"], at - 30))
            elif op in ("foe_strip", "foe_div", "turncoat"):
                out.append((op, at - 30))
            elif op == "weapon" and g["id"] == "smg":
                out.append(("smg", at - 30))
            elif op == "power" and g["id"] == "bomb":
                out.append(("bomb", at - 30))
    elif ev["type"] == "obstacle":
        out.append((ev["kind"], at - 28))
    elif ev["type"] == "wave":
        for g in ev["groups"]:
            # A lieutenant is a boss group of his own kind: his own hint (if HINTS has one),
            # never the district boss's.
            out.append(("lieutenant" if g.get("lieutenant") else g["enemy"], at - 8))
            if level and fires_back_by_district(g["enemy"], level):
                out.append(("return_fire", at - 8))
    return out


# ------------------------------------------------------------------ levels 1-3 (hand-written)

# Spec v2 section 2: levels 1-3 open with the hero alone against a small gang, before any
# follower joins. Sized with the sim (hero 1 dmg x 3/s; cold 0.4 of that): L1's falls to a
# light tapper (1.5 taps/s), L2's and L3's only to a tapping hero (about 4/s); a non-tapper
# loses all three. "fixed": calibration never rescales them.
OPENING = {1: 5, 2: 8, 3: 9}
# Levels 2-3 open hero-alone and are decided in the first seconds: the hero starts half warm
# (LevelSim tap_heat), so a casual 2 taps/s wins while 0-1 taps/s still loses (review, v2 §2).
START_HEAT = {2: 0.5, 3: 0.5}
OPENING_SHIFT = 28  # metres levels 2-3 move down the street to make room for the opening gang


def opening(level: int) -> list[dict]:
    return [{"at": 30, "type": "wave", "fixed": True, "groups": [{"enemy": "thug", "n": OPENING[level]}]}]


def shift(ev: list[dict], m: int) -> list[dict]:
    for e in ev:
        e["at"] = int(e["at"]) + m
    return ev


# Spec v2.1 §5: L1 for adults. 45-50 s, 5 gate rows. Danger beats: the hero alone against the
# opening gang (the tap lesson: about 1.5 taps/s for 6-8 s), the gang right behind the trap row
# (about 20 s), a big gang (about 35 s), and a gang leader at the end. The trap row: a x2 lane
# next to a + lane that leaves a bigger squad; the doubled squad cannot beat the gang behind it.
# Every gang is hand-sized ("fixed": calibration never rescales L1).
# Sized with the sim (_local/levels/probe_l1.gd): 1.5 taps/s clears the opening in about 6.4 s and 0
# taps falls at 3.6 s; at the trap the +40 lane loses nothing while x2 (or the red gate) loses
# about 55%; the leader soaks the best route's fire and lands his blow, so a best-lane player
# keeps about 81% of his peak (the tutorial band, spec v2.1 §2).
L1 = {"open": (5, 5, 30), "trap": 345, "big": (260, 160), "last": 500, "leader_hp": 2000, "leader_power": 45,
      "leader_gap": 14}


def level_1() -> dict:
    o1, o2, gap = L1["open"]
    big_t, big_k = L1["big"]
    ev = [
        {"at": 30, "type": "wave", "fixed": True, "groups": [
            {"enemy": "thug", "n": o1}, {"enemy": "thug", "n": o2, "gap": gap}]},
        {"at": 34, "type": "hint", "id": "swipe", "icon": "swipe"},
        {"at": 84, "type": "gates", "tutorial": "swipe", "gates": [
            {"lane": 0, "op": "num", "v": 4}, {"lane": 1, "op": "num", "v": -1, "step": 0.5, "max": 3},
            {"lane": 2, "op": "num", "v": 10}]},
        {"at": 112, "type": "wave", "fixed": True, "groups": [{"enemy": "thug", "n": 30}]},
        {"at": 136, "type": "gates", "gates": [
            {"lane": 0, "op": "num", "v": 5}, {"lane": 1, "op": "num", "v": 8},
            # a small red gate where the first gate choice (+10, lane 2) leaves the squad: the
            # red-gate lesson comes early for every new player (v1.1 tutorial fix)
            {"lane": 2, "op": "num", "v": -3, "step": 4, "max": 9}]},
        # The trap row: x2 looks big, but +40 leaves more troops for the gang right behind it.
        {"at": 164, "type": "gates", "trap": True, "gates": [
            {"lane": 0, "op": "mul", "k": 2}, {"lane": 1, "op": "num", "v": 40},
            {"lane": 2, "op": "num", "v": -10, "step": 2.5, "max": 20}]},
        {"at": 188, "type": "wave", "fixed": True, "groups": [{"enemy": "thug", "n": L1["trap"]}]},
        {"at": 236, "type": "gates", "gates": [
            {"lane": 0, "op": "num", "v": 25}, {"lane": 1, "op": "mul", "k": 2},
            {"lane": 2, "op": "num", "v": -12, "step": 3, "max": 24}]},
        {"at": 276, "type": "wave", "fixed": True, "label": "BIG GANG", "groups": [
            {"enemy": "thug", "n": big_t}, {"enemy": "thug", "n": big_k, "gap": 12}]},
        {"at": 314, "type": "gates", "gates": [
            {"lane": 0, "op": "num", "v": -15, "step": 3, "max": 30}, {"lane": 1, "op": "num", "v": 40},
            {"lane": 2, "op": "mul", "k": 2}]},
        {"at": 344, "type": "wave", "fixed": True, "label": "LAST STAND", "groups": [
            {"enemy": "thug", "n": L1["last"]},
            {"enemy": "thug", "n": 1, "gap": L1["leader_gap"], "hp": L1["leader_hp"], "power": L1["leader_power"]}]},
        {"at": 384, "type": "finish"},
    ]
    return {"_design": "First Blood. Teaches: tap to throw faster (the hero alone vs the opening gang), move, "
                       "+N vs x2 (the trap row: x2 looks bigger, but the + lane leaves more troops for the gang "
                       "right behind), shooting a red gate until it flips. Danger beats at about 8, 20 and 35 s "
                       "and the gang's leader at the end.",
            "events": ev, "charges": {}, "min_secs": 0.0}


def level_2() -> dict:
    ev = [
        {"at": 36, "type": "gates", "gates": [
            {"lane": 0, "op": "num", "v": 8}, {"lane": 1, "op": "num", "v": -2, "step": 0.6, "max": 6},
            {"lane": 2, "op": "num", "v": 5}]},
        {"at": 70, "type": "wave", "groups": [{"enemy": "thug", "n": 30}]},
        {"at": 100, "type": "gates", "gates": [
            {"lane": 0, "op": "mul", "k": 3}, {"lane": 2, "op": "num", "v": 12}]},
        {"at": 100, "type": "obstacle", "kind": "pothole", "lane": 1, "fall": 5},
        {"at": 126, "type": "gates", "gates": [
            {"lane": 0, "op": "num", "v": 12}, {"lane": 2, "op": "mul", "k": 3}]},
        {"at": 126, "type": "obstacle", "kind": "pothole", "lane": 1, "fall": 8},
        {"at": 162, "type": "wave", "groups": [{"enemy": "thug", "n": 70}, {"enemy": "knifer", "n": 50, "gap": 8}]},
        {"at": 196, "type": "gates", "gates": [
            {"lane": 1, "op": "num", "v": 20}, {"lane": 2, "op": "mul", "k": 2}]},
        {"at": 196, "type": "obstacle", "kind": "pothole", "lane": 0, "fall": 12},
        {"at": 232, "type": "wave", "groups": [{"enemy": "knifer", "n": 120}]},
        {"at": 266, "type": "gates", "gates": [
            {"lane": 0, "op": "mul", "k": 2}, {"lane": 1, "op": "num", "v": -14, "step": 3, "max": 20, "inc": 2},
            {"lane": 2, "op": "num", "v": 30}]},
        {"at": 302, "type": "wave", "groups": [{"enemy": "thug", "n": 140}, {"enemy": "knifer", "n": 70, "gap": 8}]},
        {"at": 336, "type": "gates", "gates": [
            {"lane": 0, "op": "num", "v": 30}, {"lane": 2, "op": "mul", "k": 2}]},
        {"at": 336, "type": "obstacle", "kind": "pothole", "lane": 1, "fall": 20},
        {"at": 374, "type": "wave", "groups": [{"enemy": "knifer", "n": 200}]},
        {"at": 406, "type": "gates", "gates": [
            {"lane": 0, "op": "num", "v": -20, "step": 4, "max": 30, "inc": 2}, {"lane": 1, "op": "mul", "k": 2},
            {"lane": 2, "op": "num", "v": 40}]},
        {"at": 448, "type": "wave", "label": "RUSH", "groups": [
            {"enemy": "thug", "n": 160}, {"enemy": "knifer", "n": 160, "gap": 8}]},
        {"at": 480, "type": "finish"},
    ]
    return {"_design": "Potholes. Teaches: steer around a pothole, x3, add-then-multiply (rows 2-3: +12 then x3 "
                       "beats x3 then +12), fast knifers. Opens with the hero alone against a gang only a "
                       "tapping hero beats.", "events": opening(2) + shift(ev, OPENING_SHIFT), "charges": {}}


def level_3() -> dict:
    ev = [
        {"at": 36, "type": "gates", "gates": [
            {"lane": 0, "op": "num", "v": 10}, {"lane": 2, "op": "mul", "k": 3}]},
        {"at": 36, "type": "obstacle", "kind": "pothole", "lane": 1, "fall": 3},
        {"at": 70, "type": "wave", "groups": [{"enemy": "thug", "n": 34}, {"enemy": "gunman", "n": 6, "gap": 10}]},
        {"at": 104, "type": "gates", "gates": [
            {"lane": 0, "op": "mul", "k": 2}, {"lane": 1, "op": "num", "v": 14},
            {"lane": 2, "op": "num", "v": -8, "step": 2, "max": 14, "inc": 2}]},
        {"at": 138, "type": "obstacle", "kind": "barrel", "lane": 1, "hp": 10, "radius": 8, "kill": 60, "dmg": 4},
        {"at": 150, "type": "wave", "groups": [{"enemy": "thug", "n": 90}]},
        {"at": 184, "type": "gates", "gates": [
            {"lane": 0, "op": "num", "v": 24}, {"lane": 1, "op": "mul", "k": 2}]},
        {"at": 184, "type": "obstacle", "kind": "pothole", "lane": 2, "fall": 10},
        {"at": 220, "type": "wave", "groups": [{"enemy": "knifer", "n": 80}, {"enemy": "gunman", "n": 10, "gap": 10}]},
        {"at": 254, "type": "gates", "gates": [
            {"lane": 0, "op": "power", "id": "shield", "n": 1}, {"lane": 2, "op": "num", "v": 30}]},
        {"at": 254, "type": "obstacle", "kind": "barrel", "lane": 1, "hp": 12, "radius": 8, "kill": 80, "dmg": 6},
        {"at": 290, "type": "wave", "groups": [{"enemy": "thug", "n": 150}]},
        {"at": 322, "type": "gates", "gates": [
            {"lane": 0, "op": "mul", "k": 2}, {"lane": 1, "op": "num", "v": -16, "step": 3, "max": 24, "inc": 2},
            {"lane": 2, "op": "num", "v": 40}]},
        {"at": 360, "type": "wave", "groups": [{"enemy": "knifer", "n": 120}, {"enemy": "gunman", "n": 14, "gap": 10}]},
        {"at": 394, "type": "gates", "gates": [
            {"lane": 1, "op": "num", "v": 40}, {"lane": 2, "op": "mul", "k": 2}]},
        {"at": 394, "type": "obstacle", "kind": "pothole", "lane": 0, "fall": 24},
        {"at": 436, "type": "wave", "label": "CROSSFIRE", "groups": [
            {"enemy": "thug", "n": 180}, {"enemy": "gunman", "n": 20, "gap": 10}]},
        {"at": 470, "type": "finish"},
    ]
    return {"_design": "Crossfire. Teaches: gunmen stop and shoot (SHIELD blocks them), barrels blow up gangs "
                       "running past them, a power gate. Opens with the hero alone against a gang only a "
                       "tapping hero beats.", "events": opening(3) + shift(ev, OPENING_SHIFT), "charges": {"shield": 1}}


HAND = {1: level_1, 2: level_2, 3: level_3}


# ------------------------------------------------------------------ generated levels

def mix_kinds(name: str) -> set:
    return {e for e, _, _ in MIXES[name]}


def pick_mix(rng: random.Random, mixes: list[str], newest: str, rules: dict, need: set) -> str:
    """The next gang's mix. `need` = enemy kinds the level still has to show (a debut, or every
    kind for the Hard gauntlet): the mix covering most of them wins. Otherwise the newest enemy
    shows up three times as often, times the archetype's own weights."""
    if need:
        best = max(mixes, key=lambda m: len(need & mix_kinds(m)))
        if need & mix_kinds(best):
            return best
    weights = rules.get("mixes", {})
    wts = [(3.0 if newest in mix_kinds(m) else 1.0) * weights.get(m, 1.0) for m in mixes]
    return rng.choices(mixes, wts)[0]


def make_cage(rng: random.Random, sq: Sq, level: int, at: float, diff: float) -> dict:
    """A hostage cage (Rescue): guards sized so the planned squad needs about 3 s of fire to cut
    them down (the cage reaches the squad about 5.5 s after they come in range), and hostages
    worth a good gate. The planned (greedy) squad frees them."""
    kinds = [e for e in CAGE_GUARDS if int(ENEMIES[e]["unlock"]) < level]
    enemy = rng.choice(kinds)
    n = screen_size(sq, enemy, 2.6 + 0.8 * diff)
    hostages = nice(max(4, grow_base(sq) * rng.uniform(0.35, 0.55)))
    sq.add("constable", hostages)
    return {"at": at, "type": "cage", "lane": rng.randrange(3), "hostages": hostages,
            "guards": {"enemy": enemy, "n": n}}


def generate(level: int) -> dict:
    rng = random.Random(1000 + level)
    d = district(level)
    i = index_in_district(level)
    boss = is_boss(level)
    arch = archetype(level)
    R = ARCH.get(arch, {})
    diff = difficulty(level)
    sq = Sq(d)
    events: list[dict] = []
    ctx: dict = {"debut_rank": debut_rank(level), "car_due": level == CAR_LEVEL, "mul_every": bool(R.get("mul_every")),
                 "mul_w": R.get("mul_w", 2.2), "obstacle_w": R.get("obstacle_w", {})}
    speed = S0 * float(R.get("speed", 1.0))
    run_secs = float(R.get("secs", 64 + 14 * (level - 1) / (LEVELS - 1)))
    track = run_secs * speed - (60 if boss else 0)
    row_gap = int(R.get("row_gap", 26))
    wave_after = int(R.get("wave_after", 34))
    next_gap = int(R.get("next_gap", 30))
    combo_p = float(R.get("combo_p", 0.3))
    loss_k = float(R.get("loss_k", 1.0))
    pos = 36
    lucky_left = 1 if level % LUCKY_EVERY == 1 else 0
    lucky_beat = rng.randrange(2, 5)
    mixes = [m for m in MIXES if mix_ok(m, level)]
    newest_enemy = max((e for e in ENEMIES if int(ENEMIES[e]["unlock"]) <= level and e != "boss"),
                       key=lambda e: int(ENEMIES[e]["unlock"]))
    beats = int(R.get("beats", max(5, int(round((track - 70) / 68.0)))))
    if "beats_k" in R:
        beats = max(4, int(round(beats * float(R["beats_k"]))))
    # Kinds the level must show: a debut (its unlock level), or every kind so far (Hard gauntlet).
    need: set = set()
    if debut_enemy(level):
        need.add(debut_enemy(level))
    if R.get("all_kinds"):
        need |= {e for e in ENEMIES if e != "boss" and int(ENEMIES[e]["unlock"]) <= level}
        beats = max(beats, len(need) // 2 + 2)
    cage_beats: set = set()
    if R.get("cages"):
        cage_beats = set(rng.sample(range(2, beats - 1), min(int(R["cages"]), max(beats - 3, 0))))
    beat = 0
    prev_kinds: list[str] = []
    prev_add = None
    last_arrival = pos
    while beat < beats:
        last = beat == beats - 1
        cage = beat in cage_beats
        # Next wave's mix first (foe mods in the row before it need to know it).
        if beat == 0:
            # The first gang is the plain screen, except an Ambush's: armed or fast.
            mix_name = "crowd"
            if R.get("opening"):
                mix_name = rng.choice([m for m in ("gunline", "fast", "bikers") if m in mixes] or ["crowd"])
        elif last and not boss and not need:
            hard = [m for m in mixes if m in ("gunline", "grenadiers", "siege", "warband", "molotov", "snipers", "brutes", "riot")]
            mix_name = rng.choice(hard or mixes)
        else:
            mix_name = pick_mix(rng, mixes, newest_enemy, R, need)
        mix = MIXES[mix_name]
        ctx["next_armour"] = any(int(ENEMIES[e]["armour"]) > 0 for e, _, _ in mix) and not cage

        combo = beat > 0 and not last and rng.random() < combo_p
        n_rows = 2 if combo else 1
        for r in range(n_rows):
            at = pos + row_gap * r
            n_off = 2
            if lucky_left and beat == lucky_beat and r == 0:
                n_off = 3
                lucky_left = 0
            elif rng.random() < 0.12 + 0.3 * diff + float(R.get("one_offer", 0.0)) and not (beat == 0 and r == 0):
                n_off = 1
            lanes = [0, 1, 2]
            rng.shuffle(lanes)
            offer_lanes = sorted(lanes[:n_off])
            kinds = offer_kinds(rng, level, n_off, ctx)
            if combo and r == 1 and len(prev_kinds) == 2 and set(prev_kinds) == {"add", "mul"} and n_off == 2:
                kinds = ["mul", "add"] if prev_kinds[0] == "add" else ["add", "mul"]
            gates = []
            for lane, kind in zip(offer_lanes, kinds):
                g = offer(rng, kind, sq, lane, level, ctx)
                if kind == "weapon":
                    ctx["weapon_done"] = True
                gates.append(g)
            if combo and r == 1:
                # Operation order: the same +N as the row before, swapped against x2.
                for g in gates:
                    if g["op"] == "num" and prev_add is not None:
                        g["v"] = prev_add
            obstacles = []
            for lane in lanes[n_off:]:
                first_row = beat == 0 and r == 0
                ob = None if first_row else lane_obstacle(rng, sq, lane, at, level, beat < 2, ctx)
                if first_row:
                    # The squad is tiny at the start: only a small red gate the hero can flip.
                    gates.append({"lane": lane, "op": "num", "v": -rng.choice([1, 2]), "step": 0.5, "max": rng.choice([4, 5, 6])})
                elif ob is None:
                    gates.append(red_gate(rng, sq, lane, level, beat < 2))
                else:
                    obstacles.append(ob)
            # A barricade guarding an offer: break it or lose the gate behind it.
            if level >= 4 and beat > 0 and rng.random() < float(R.get("guard_p", 0.18)):
                g = rng.choice([g for g in gates if g["op"] not in ("num", "pct") or g.get("v", 0) > 0])
                dps = max(sq.dps(0, 1000.0, 1), 3.0)
                guard = {"at": at - 8, "type": "obstacle", "kind": "barricade", "lane": g["lane"],
                         "hp": nice(max(6, dps * 1.4)), "block_reach": 12}
                if level >= 6:
                    guard["dmg_pct"] = rng.choice([10, 15])
                else:
                    guard["dmg"] = nice(max(3, sq.total() * 0.12))
                obstacles.append(guard)
            gates.sort(key=lambda g: g["lane"])
            events.append({"at": at, "type": "gates", "gates": gates})
            events.extend(obstacles)
            prev_kinds = kinds
            prev_add = next((g["v"] for g in gates if g["op"] == "num" and g.get("v", 0) > 0), None)
            pick = best_choice(sq, gates)
            if pick is not None:
                apply_gate(sq, pick)
        wave_at = pos + row_gap * (n_rows - 1) + wave_after
        if beat == 0 and R.get("opening"):
            # Ambush: the gang is already in fire range while the squad runs at the first row.
            wave_at = pos + 16
        if cage:
            events.append(make_cage(rng, sq, level, wave_at, diff))
            last_arrival = wave_at
            pos = int(wave_at + next_gap + rng.randint(-3, 3))
            beat += 1
            continue
        need -= mix_kinds(mix_name)
        # Loss target for this wave: grows through the level and with difficulty.
        frac = beat / max(beats - 1, 1)
        loss = (0.05 + 0.12 * diff) * (0.6 + 0.8 * frac) * loss_k
        if last and not boss:
            loss = (0.28 + 0.22 * diff) * loss_k
        if last and arch == "lieutenant":
            # His crew is sized from the planned squad (sq becomes the squad after it).
            wave = lieutenant_wave(level, d, sq, wave_at)
            gap = max(float(g.get("gap", 0)) for g in wave["groups"])
            events.append(wave)
            last_arrival = wave_at + gap
            pos = int(wave_at + next_gap + rng.randint(-3, 3))
            beat += 1
            continue
        pincer = 0 < beat < beats - 2 and rng.random() < float(R.get("pincer_p", 0.0))
        groups, sq = size_wave(sq, mix, loss * (0.6 if pincer else 1.0), 0.8 + 1.6 * diff)
        wave = {"at": wave_at, "type": "wave", "groups": groups}
        if last and not boss:
            wave["label"] = rng.choice([b for b in WAVE_BANNERS if not (R.get("opening") and b == "AMBUSH")])
        elif beat == 0 and R.get("opening"):
            wave["label"] = "AMBUSH"
        elif arch == "horde" and beat == 1:
            wave["label"] = "BIG GANG"
        events.append(wave)
        last_arrival = wave_at + max(g.get("gap", 0) for g in groups)
        if pincer:
            # A second gang right behind the first: the squad is caught between two fires.
            mix2 = MIXES[pick_mix(rng, mixes, newest_enemy, R, set())]
            groups2, sq = size_wave(sq, mix2, loss * 0.6, 0.8 + 1.6 * diff)
            at2 = int(last_arrival + 16)
            events.append({"at": at2, "type": "wave", "groups": groups2})
            last_arrival = at2 + max(g.get("gap", 0) for g in groups2)
            wave_at = at2
        pos = int(wave_at + next_gap + rng.randint(-3, 3))
        beat += 1

    if boss:
        # Last row: a power and a boost; then the boss walks out of the HQ behind his crew.
        at = pos
        lanes = [0, 1, 2]
        rng.shuffle(lanes)
        gates = [offer(rng, "mul" if sq.total() < max(90, cap_of(d) * 3 // 10) else "recruit", sq, lanes[0], level, ctx),
                 {"lane": lanes[1], "op": "power", "id": "bomb", "n": 1}]
        gates.append(red_gate(rng, sq, lanes[2], level))
        gates.sort(key=lambda g: g["lane"])
        events.append({"at": at, "type": "gates", "gates": gates})
        pick = best_choice(sq, gates)
        if pick is not None:
            apply_gate(sq, pick)
        crew_mix = MIXES[rng.choice([m for m in mixes if m in ("crowd", "fast", "brutes", "riot")])]
        crew, after = size_wave(sq, crew_mix, 0.12 + 0.08 * diff, 1.0 + diff)
        # Boss health (spec v2.1 section 1.3): boss.hp_secs of the expected squad's fire. Here the
        # planned squad's; build() replaces it with the calibrated boss_dps (the real squad on the
        # stored route at the pace) once calibration.json has it. His gun and barrage take a
        # share of the squad (units.json boss), so they need no per-level numbers.
        dps_boss = max(after.dps(int(ENEMIES["boss"]["armour"]), float(ENEMIES["boss"]["hp"]), 1), 5.0)
        boss_grp = {"enemy": "boss", "n": 1, "gap": 22, "hp": boss_hp(d, dps_boss)}
        # His fists grow with the district's cap (a 100K squad must still feel them).
        if cap_of(d) > 1000:
            boss_grp["power"] = nice(int(ENEMIES["boss"]["power"]) * cap_of(d) / 1000.0)
        wave_at = at + 36
        events.append({"at": wave_at, "type": "wave", "label": BOSS_BANNERS[d - 1], "groups": crew + [boss_grp]})
        last_arrival = wave_at + 22
        finish = last_arrival + 26
    else:
        finish = last_arrival + 22
    events.append({"at": finish, "type": "finish"})
    charges = {}
    if level >= 3:
        charges["shield"] = 1
    if level >= 6:
        charges["bomb"] = 2 if boss else 1
    out = {"_design": f"District {d} level {i}: {arch}{' (boss)' if boss else ''}, generated (seed {1000 + level}), "
                      f"difficulty {diff:.2f}, newest enemy {newest_enemy}.",
           "events": events, "charges": charges}
    if "speed" in R:
        out["scroll_speed"] = round(speed, 3)
    if "min_secs" in R:
        out["min_secs"] = float(R["min_secs"])
    return out


# ------------------------------------------------------------------ output

def stretch(events: list[dict], min_m: float = MIN_SECS * S0) -> None:
    """Spreads a short level out (every `at` x f) so its track is at least min_m metres."""
    finish = max(float(e["at"]) for e in events if e["type"] == "finish")
    f = min_m / finish
    if f <= 1.0:
        return
    for e in events:
        e["at"] = int(round(float(e["at"]) * f))


def build(level: int, seen: set, cal_all: dict) -> dict:
    cal = cal_all.get(str(level), {})
    lv = HAND[level]() if level in HAND else generate(level)
    events = lv["events"]
    speed = float(lv.get("scroll_speed", S0))
    stretch(events, float(lv.get("min_secs", MIN_SECS)) * speed)
    apply_scale(events, float(cal.get("k", 1.0)), float(cal.get("kf", 1.0)))
    apply_boss_hp(events, level, cal)
    # One-time icon hints: the first time ever each mechanic shows up. A bomb charge at the
    # start counts as the bomb's debut: point at its button before the first wave.
    hints = []
    if int(lv["charges"].get("bomb", 0)) > 0 and "bomb" not in seen:
        first_wave = min(float(e["at"]) for e in events if e["type"] == "wave")
        events.append({"at": max(4, int(first_wave) - 6), "type": "hint", "id": "bomb", "icon": "bomb", "power": "bomb"})
        seen.add("bomb")
    have = {e.get("id") for e in events if e["type"] == "hint"}
    for e in list(events):
        for mech, at in mechanics_of(e, level):
            if mech in seen or mech not in HINTS:
                continue
            seen.add(mech)
            hid, icon, power = HINTS[mech]
            if hid in have:
                continue
            h = {"at": max(4, int(round(at))), "type": "hint", "id": hid, "icon": icon}
            if power:
                h["power"] = power
            if e["type"] == "wave":
                # The sim shows an enemy hint when that gang comes within fire range + 10 m
                # (its `at` is only the fallback): a boss halts the street before its wave's at.
                h["enemy"] = mech if mech != "return_fire" else next(
                    g["enemy"] for g in e["groups"] if fires_back_by_district(g["enemy"], level))
            hints.append(h)
            have.add(hid)
    events = sorted(events + hints, key=lambda e: (float(e["at"]), e["type"] != "hint"))
    d = district(level)
    out = {
        "_design": lv["_design"],
        "id": level,
        "name": NAMES[level - 1],
        "district": d,
        "boss": is_boss(level),
        "archetype": archetype(level),
        "target_win": round(target_win(level), 2),
        "target_ratio": target_ratio(level),
        "stars": star_thresholds(level, cal),
        "charges": lv["charges"],
    }
    look = ARCH.get(archetype(level), {}).get("look")
    if look:
        out["look"] = look
    if "scroll_speed" in lv:
        out["scroll_speed"] = lv["scroll_speed"]
    if need_upgrades(level):
        out["need_upgrades"] = True
    if level in START_HEAT:
        out["start_heat"] = START_HEAT[level]
    # The level's enemy fire intensity (LevelSim.fire_k), fitted by tests/tune.gd calibrate=1.
    fk = float(cal.get("fire_k", 1.0))
    if abs(fk - 1.0) > 1e-9:
        out["fire_k"] = round(fk, 4)
    if cal.get("coin_ref"):
        out["coin_ref"] = int(cal["coin_ref"])
    # A lane route tests/tune.gd found to win (route_np: without powers, levels 1-10).
    for key in ("route", "route_np"):
        if cal.get(key):
            out[key] = cal[key]
    out["events"] = events
    return out


def dump(lv: dict) -> str:
    lines = ["{"]
    keys = [k for k in lv if k != "events"]
    for k in keys:
        lines.append(f"  {json.dumps(k)}: {json.dumps(lv[k], ensure_ascii=False)},")
    lines.append('  "events": [')
    evs = lv["events"]
    for n, e in enumerate(evs):
        lines.append("    " + json.dumps(e, ensure_ascii=False) + ("," if n < len(evs) - 1 else ""))
    lines.append("  ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def merge(paths: list[str]) -> None:
    """Folds tests/tune.gd calibrate=1 reports into calibration.json."""
    cal = load_calibration()
    for p in paths:
        for r in json.loads(Path(p).read_text(encoding="utf-8")):
            key = str(int(r["level"]))
            old = cal.get(key, {})
            if "k" not in r:
                # A tools/boss_dps.gd report: only the boss HP rule's expected dps changes.
                if float(r.get("boss_dps", 0.0)) > 0:
                    cal[key] = dict(old, boss_dps=round(float(r["boss_dps"]), 1))
                continue
            entry = {"k": round(float(old.get("k", 1.0)) * float(r["k"]), 4),
                     "kf": round(float(old.get("kf", 1.0)) * float(r.get("kf", 1.0)), 4),
                     "fire_k": round(float(old.get("fire_k", 1.0)) * float(r.get("fire_k", 1.0)), 4),
                     "best_ratio": round(float(r["best_ratio"]), 3),
                     "win_rate": round(float(r["win_rate"]), 3)}
            # Spec v2.1 §2 fits (tune.gd profile=greedy|noisy): the level's band, the greedy
            # player's end / peak squad, the noisy player's first-try fail rate, and whether
            # the no-ad route held. A record for the next calibration; build() ignores them.
            if r.get("band"):
                entry["band"] = str(r["band"])
            for fk in ("greedy_keep", "noisy_fail"):
                if fk in r:
                    entry[fk] = round(float(r[fk]), 3)
            if "noad" in r:
                entry["noad"] = bool(r["noad"])
            # Routes are only valid for the exact level they were found on: keep them from
            # a plain report (k = kf = 1), drop them when the gangs were rescaled.
            plain = all(abs(float(r.get(f, 1.0)) - 1.0) < 1e-9 for f in ("k", "kf", "fire_k"))
            if plain:
                for rk in ("route", "route_np"):
                    if r.get(rk):
                        entry[rk] = [int(x) for x in r[rk]]
                # The stored route's finishing squad: LevelSim.coin_troops pays it like a full
                # district-1 squad (most levels end far below their district's cap). A v2.1
                # report's stored route is its no-power route (route_troops), not its best.
                troops = int(r.get("route_troops", r.get("best_troops", 0)))
                if r.get("route") and troops > 0:
                    entry["coin_ref"] = troops
            # Spec v2.1 section 1.3: the boss HP rule's expected dps (Autopilot.boss_dps), kept
            # until a report measures it again.
            if float(r.get("boss_dps", 0.0)) > 0:
                entry["boss_dps"] = round(float(r["boss_dps"]), 1)
            elif old.get("boss_dps"):
                entry["boss_dps"] = old["boss_dps"]
            cal[key] = entry
    ordered = {k: cal[k] for k in sorted(cal, key=int)}
    CAL_PATH.write_text(json.dumps(ordered, indent=1) + "\n", encoding="utf-8", newline="\n")
    print(f"calibration: {len(ordered)} levels")


def main(argv: list[str]) -> None:
    if argv and argv[0] == "--merge":
        merge(argv[1:])
        argv = []
    lo, hi = 1, LEVELS
    if len(argv) >= 1:
        lo = int(argv[0])
        hi = int(argv[1]) if len(argv) >= 2 else lo
    cal = load_calibration()
    seen: set = {"swipe"}
    for level in range(1, LEVELS + 1):
        lv = build(level, seen, cal)
        if lo <= level <= hi:
            (OUT / f"level_{level}.json").write_text(dump(lv), encoding="utf-8", newline="\n")
    print(f"wrote levels {lo}..{hi}")


if __name__ == "__main__":
    main(sys.argv[1:])
