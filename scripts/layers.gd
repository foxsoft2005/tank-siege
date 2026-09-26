class_name Layers
extends RefCounted
## Physics layer bit values, named so the code reads clearly.
## Each physics object says which layer it LIVES on (collision_layer)
## and which layers it BUMPS INTO (collision_mask).

const WALLS := 1      # brick, steel, map border
const WATER := 2      # blocks tanks, but bullets fly over it
const TANKS := 4
const BASE := 8
const BULLETS := 16
const POWERUPS := 32
const AIR := 64       # flying things (the gunship boss): only shells hit them
