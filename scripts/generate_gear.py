#!/usr/bin/env python3
"""Generate gear_catalog_seed.json with popular fishing gear."""

import json
import os

gear = []
gid = 1

def add(category, brand, model, type_=None, specs=None, target=None, price=None):
    global gid
    gear.append({
        "id": gid,
        "category": category,
        "brand": brand,
        "model": model,
        "type": type_,
        "specs": specs,
        "targetSpecies": target,
        "priceRange": price
    })
    gid += 1

# === RODS ===
# Spinning rods
add("Rod", "Shimano", "Zodias 6'8\" M", "Spinning", "2-piece, fast action", "Bass, Walleye", "$$")
add("Rod", "St. Croix", "Premier PS70MF", "Spinning", "7' Medium Fast", "Bass, Trout", "$$")
add("Rod", "Daiwa", "Tatula XT 7' M", "Spinning", "1-piece, fast action", "Bass, Pike", "$$")
add("Rod", "G. Loomis", "NRX+ 6'8\" ML", "Spinning", "Fast action, fuji guides", "Bass, Trout", "$$$$")
add("Rod", "Fenwick", "HMG 7' M", "Spinning", "Graphite blank, fast", "Bass, Walleye", "$$")
add("Rod", "Ugly Stik", "GX2 7' M", "Spinning", "Fiberglass/graphite", "All species", "$")
add("Rod", "Abu Garcia", "Veritas 7' MH", "Spinning", "30-ton graphite", "Bass, Pike", "$$")
add("Rod", "Penn", "Battle III 7' MH", "Spinning", "Graphite composite", "Saltwater, Redfish", "$$")
add("Rod", "Okuma", "Celilo 6'6\" L", "Spinning", "Ultra-light", "Trout, Panfish", "$")
add("Rod", "Shakespeare", "Ugly Stik Elite 6'6\" M", "Spinning", "Clear tip, sensitive", "Bass, Trout", "$")

# Baitcasting rods
add("Rod", "Shimano", "Expride 7' MH", "Baitcasting", "Fast action, 1-piece", "Bass", "$$$")
add("Rod", "Dobyns", "Champion XP 7'3\" MH", "Baitcasting", "Fast, high modulus", "Bass", "$$$")
add("Rod", "Megabass", "Destroyer P5 7'", "Baitcasting", "Multi-taper action", "Bass", "$$$$")
add("Rod", "Abu Garcia", "Vendetta 7' MH", "Baitcasting", "24-ton graphite", "Bass, Pike", "$$")
add("Rod", "Lew's", "Mach II 7'2\" MH", "Baitcasting", "IM8 graphite", "Bass", "$$")

# Fly rods
add("Rod", "Orvis", "Clearwater 9' 5wt", "Fly", "4-piece, medium-fast", "Trout", "$$")
add("Rod", "Redington", "Classic Trout 8'6\" 4wt", "Fly", "4-piece, moderate", "Trout", "$")
add("Rod", "Sage", "X 9' 5wt", "Fly", "Fast action, KonneticHD", "Trout, Bass", "$$$")
add("Rod", "TFO", "Pro II 9' 6wt", "Fly", "4-piece, fast action", "Trout, Steelhead", "$$")

# Surf/saltwater rods
add("Rod", "Penn", "Prevail II 10' Surf", "Surf", "2-piece, moderate-fast", "Stripers, Bluefish", "$$")
add("Rod", "Daiwa", "BG Saltwater 7' MH", "Saltwater", "Heavy-duty blanks", "Tuna, Mahi", "$$")
add("Rod", "Shimano", "Teramar Southeast 7'", "Saltwater", "Inshore, fast action", "Redfish, Snook", "$$")

# === REELS ===
# Spinning reels
add("Reel", "Shimano", "Stradic FL 2500", "Spinning", "6.0:1, 9+1 bearings", "Bass, Trout", "$$$")
add("Reel", "Daiwa", "Tatula LT 2500", "Spinning", "5.3:1, light 7.4oz", "Bass, Walleye", "$$")
add("Reel", "Penn", "Battle III 3000", "Spinning", "6.2:1, HT-100 drag", "Saltwater, Stripers", "$$")
add("Reel", "Shimano", "Vanford 2500", "Spinning", "6.0:1, 7+1 bearings", "Bass, Trout", "$$$")
add("Reel", "Abu Garcia", "Revo SX 30", "Spinning", "6.2:1, 8+1 bearings", "Bass", "$$")
add("Reel", "Pflueger", "President 30", "Spinning", "5.2:1, 10 bearings", "Trout, Panfish", "$")
add("Reel", "Daiwa", "BG 4000", "Spinning", "5.7:1, oversized gears", "Saltwater, Kingfish", "$$")
add("Reel", "Shimano", "Sedona 1000", "Spinning", "5.0:1, lightweight", "Trout, Panfish", "$")
add("Reel", "Okuma", "Ceymar C-30", "Spinning", "6.0:1, 8 bearings", "Bass, Walleye", "$")

# Baitcasting reels
add("Reel", "Shimano", "Curado DC 200", "Baitcasting", "6.2:1, digital control", "Bass", "$$$$")
add("Reel", "Daiwa", "Tatula SV TW 103", "Baitcasting", "6.3:1, T-Wing", "Bass", "$$$")
add("Reel", "Lew's", "Mach Crush SLP 7.5:1", "Baitcasting", "10+1 bearings", "Bass", "$$")
add("Reel", "Abu Garcia", "Revo Rocket 10.1:1", "Baitcasting", "Extra high speed", "Bass", "$$$")
add("Reel", "Shimano", "SLX DC 150", "Baitcasting", "Digital braking", "Bass", "$$")
add("Reel", "Shimano", "Metanium MGL 150", "Baitcasting", "5.7oz, magnumlite spool", "Bass", "$$$$")

# Fly reels
add("Reel", "Orvis", "Battenkill Disc III", "Fly", "3/4/5wt, click & pawl", "Trout", "$$")
add("Reel", "Lamson", "Liquid 3+", "Fly", "Sealed conical drag", "Trout", "$$")
add("Reel", "Ross", "Colorado LT 3/4", "Fly", "Machined aluminum", "Trout", "$$$")

# === LURES ===
# Soft plastics
add("Lure", "Yamamoto", "Senko 5\" Green Pumpkin", "Soft Plastic", "Stick bait, wacky/texas", "Bass", "$")
add("Lure", "Zoom", "Trick Worm 6\" Plum", "Soft Plastic", "Floating worm", "Bass", "$")
add("Lure", "Berkley", "PowerBait MaxScent Flat Worm", "Soft Plastic", "Scented, 4\"", "Bass", "$")
add("Lure", "Strike King", "Rage Craw 4\"", "Soft Plastic", "Creature bait", "Bass", "$")
add("Lure", "Z-Man", "TRD 2.75\"", "Soft Plastic", "Ned rig, ElaZtech", "Bass, Walleye", "$")
add("Lure", "Keitech", "Swing Impact FAT 4.8\"", "Soft Plastic", "Swimbait, squid scent", "Bass", "$")
add("Lure", "NetBait", "Baby Paca Craw", "Soft Plastic", "Flipping craw", "Bass", "$")
add("Lure", "Gulp!", "Alive Minnow 3\"", "Soft Plastic", "Biodegradable, scented", "Trout, Walleye", "$")

# Hard baits
add("Lure", "Rapala", "Original Floating 09", "Crankbait", "Balsa, 3.5\"", "Bass, Trout, Pike", "$")
add("Lure", "Megabass", "Vision ONETEN 110", "Jerkbait", "Suspending, 4.5\"", "Bass", "$$$")
add("Lure", "Lucky Craft", "Pointer 100SP", "Jerkbait", "Suspending minnow", "Bass", "$$")
add("Lure", "Strike King", "KVD Square Bill 1.5", "Crankbait", "Shallow diver", "Bass", "$")
add("Lure", "Rapala", "DT6 Crankbait", "Crankbait", "Dives to 6'", "Bass, Walleye", "$")
add("Lure", "Yo-Zuri", "3DB Popper", "Topwater", "Popping action", "Bass, Redfish", "$")
add("Lure", "Heddon", "Zara Spook", "Topwater", "Walk-the-dog", "Bass, Stripers", "$")
add("Lure", "River2Sea", "Whopper Plopper 110", "Topwater", "Rotating tail, 4.25\"", "Bass", "$$")
add("Lure", "Booyah", "Buzz Bait 3/8oz", "Topwater", "Buzzbait", "Bass", "$")

# Spinnerbaits & spoons
add("Lure", "War Eagle", "Spinnerbait 3/8oz DW", "Spinnerbait", "Double willow", "Bass", "$")
add("Lure", "Booyah", "Blade 1/2oz", "Spinnerbait", "Tandem blade", "Bass, Pike", "$")
add("Lure", "Mepps", "Aglia #3 Gold", "Inline Spinner", "French spinner", "Trout, Panfish", "$")
add("Lure", "Blue Fox", "Vibrax #4 Silver", "Inline Spinner", "Vibrating blade", "Trout, Salmon", "$")
add("Lure", "Kastmaster", "Acme 1/4oz Gold", "Spoon", "Casting spoon", "Trout, Bass", "$")
add("Lure", "Dardevle", "Classic Red/White 1oz", "Spoon", "Trolling/casting", "Pike, Musky", "$")
add("Lure", "Johnson", "Silver Minnow 1/4oz", "Weedless Spoon", "Weedless, gold", "Bass, Pike", "$")

# Jigs
add("Lure", "Strike King", "Bitsy Bug Jig 3/16oz", "Jig", "Finesse jig", "Bass", "$")
add("Lure", "Dirty Jigs", "Football Jig 1/2oz", "Jig", "Football head", "Bass", "$")
add("Lure", "Z-Man", "Finesse ShroomZ 1/4oz", "Jig", "Ned rig head", "Bass", "$")
add("Lure", "Owner", "Flashy Swimmer 3/8oz", "Jig", "Underspin jig", "Bass, Walleye", "$")
add("Lure", "VMC", "Tokyo Rig 3/8oz", "Jig", "Tokyo rig head", "Bass", "$")

# Swimbaits
add("Lure", "S Waver", "168 Jointed 6.5\"", "Swimbait", "Glide bait, slow sink", "Bass, Pike", "$$$")
add("Lure", "Huddleston", "ROF 5 Trout 8\"", "Swimbait", "Trout imitation", "Bass", "$$$$")
add("Lure", "Savage Gear", "4D Trout Rattle 6.5\"", "Swimbait", "Jointed, rattle", "Bass, Pike", "$$")

# === BAIT ===
add("Bait", "Berkley", "PowerBait Trout Dough", "Dough Bait", "Floating, scented", "Trout", "$")
add("Bait", "Gulp!", "Alive Crawfish", "Artificial", "Scented, reusable", "Bass, Catfish", "$")
add("Bait", "Nightcrawlers", "Live Worms (dozen)", "Live Bait", "Universal bait", "All species", "$")
add("Bait", "Minnows", "Live Shiners (dozen)", "Live Bait", "Baitfish", "Bass, Walleye, Pike", "$")
add("Bait", "Berkley", "Gulp! Earthworm 6\"", "Artificial", "Scented soft bait", "Trout, Panfish", "$")
add("Bait", "Strike King", "KVD Perfect Plastics Cut-R Worm", "Cut Bait", "Soft plastic cut bait", "Bass", "$")

# === LINE ===
add("Line", "Berkley", "Trilene XL 8lb Mono", "Monofilament", "Smooth casting, 330yd", "All species", "$")
add("Line", "Sufix", "832 Advanced Superline 15lb", "Braided", "8-carrier braid, 150yd", "Bass, Pike", "$$")
add("Line", "PowerPro", "Spectra 30lb Moss Green", "Braided", "Micro-filament, 150yd", "Bass, Saltwater", "$$")
add("Line", "Seaguar", "InvizX 12lb Fluorocarbon", "Fluorocarbon", "100% fluorocarbon, 200yd", "Bass", "$$")
add("Line", "Sunline", "Sniper FC 10lb", "Fluorocarbon", "Triple resin coating", "Bass", "$$")
add("Line", "Berkley", "FireLine 10lb Crystal", "Braided", "Thermally fused", "Walleye, Bass", "$")
add("Line", "Daiwa", "J-Braid x8 20lb", "Braided", "8-strand, round profile", "Saltwater", "$$")
add("Line", "Seaguar", "AbrazX 15lb", "Fluorocarbon", "Abrasion resistant", "Bass, Rocks", "$$")
add("Line", "Rio", "Gold WF5F Fly Line", "Fly Line", "Weight-forward floating", "Trout", "$$$")

# === HOOKS ===
add("Hook", "Owner", "Offset Worm 3/0", "Offset Worm", "Super Needle Point", "Bass", "$")
add("Hook", "Gamakatsu", "EWG 4/0", "Extra Wide Gap", "Black nickel", "Bass", "$")
add("Hook", "VMC", "Neko Hook 1/0", "Weedless Neko", "With weight keeper", "Bass", "$")
add("Hook", "Mustad", "Circle Hook 5/0", "Circle", "Ultra-point, inline", "Saltwater, Catfish", "$")
add("Hook", "Eagle Claw", "Aberdeen 4", "Aberdeen", "Light wire, gold", "Panfish, Trout", "$")
add("Hook", "Trokar", "TK130 Flippin 5/0", "Flipping", "Surgically sharpened", "Bass", "$$")
add("Hook", "Hayabusa", "Frog Hook 4/0", "Frog", "Heavy wire, weedless", "Bass", "$")

# === TERMINAL TACKLE ===
add("Terminal Tackle", "Tungsten", "Drop Shot Weight 3/16oz", "Drop Shot", "Round, compact", "Bass", "$")
add("Terminal Tackle", "Strike King", "Tour Grade Tungsten 1/2oz", "Bullet Weight", "Pegged or free", "Bass", "$")
add("Terminal Tackle", "VMC", "Spin Shot Rig #1", "Drop Shot", "Free-spinning hook", "Bass, Walleye", "$")
add("Terminal Tackle", "Whisker Seeker", "No-Roll Sinker 3oz", "Sinker", "Flat, stays put", "Catfish", "$")
add("Terminal Tackle", "Water Gremlin", "Split Shot BB", "Split Shot", "Removable, reusable", "Trout, Panfish", "$")
add("Terminal Tackle", "Berkley", "Cross-Lok Snap 45lb", "Snap/Swivel", "Easy lure change", "All species", "$")

# === ACCESSORIES ===
add("Accessory", "Plano", "3600 Tackle Box", "Storage", "StowAway utility box", "All species", "$")
add("Accessory", "KastKing", "Waterproof Tackle Bag", "Bag", "3600 trays included", "All species", "$$")
add("Accessory", "Rapala", "Digital Scale 50lb", "Scale", "Backlit LCD, memory", "All species", "$")
add("Accessory", "Boomerang", "Snip Line Cutter", "Tool", "Retractable, stainless", "All species", "$")
add("Accessory", "Cuda", "Titanium Pliers 7.5\"", "Pliers", "Split ring, cutter", "All species", "$$")
add("Accessory", "Frabill", "Floating Net 21x25\"", "Net", "Conservation mesh", "Bass, Trout", "$$")
add("Accessory", "Boga Grip", "Model 315 30lb", "Lip Gripper", "Stainless, scale built-in", "Bass, Saltwater", "$$$")

output = os.path.join(os.path.dirname(__file__), "..", "ios", "Currents", "Resources", "Data", "gear_catalog_seed.json")
with open(output, "w") as f:
    json.dump(gear, f, indent=2)

print(f"Generated {len(gear)} gear items")
print(f"Written to {output}")
