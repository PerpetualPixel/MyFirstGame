class_name Story
extends RefCounted

## Every line of narrative text in one place: the intro letter, the late
## inventor's collectible notes, Mrs. Puddle's radio chatter, and the
## run-grading table. Cornelius Gearhart built the house; his housekeeper
## Mrs. Puddle waits outside on shortwave and tipped the player off.

const INTRO_TITLE := "A LETTER, SLIPPED UNDER YOUR DOOR"

const INTRO_TEXT := """To the last Gearhart with any spark left —

Uncle Cornelius is dead. The vultures in suits arrive at dawn to carve up
the estate, and his will — the REAL one — waits in the strongbox in his
vault, exactly where he promised me he'd leave it.

He built the whole house into one last game. He always said the
inheritance should go to whoever could think like him, not whoever could
afford the better lawyer.

You have until their motorcade reaches the door. I'll be on the radio.

Get in. Solve his machines. Read everything he left you.

— Mrs. P."""

const INTRO_HINT := "[E] Slip inside"

## The inventor's scattered notes, each found beside the machine it
## muses about. Collected into the [Tab] notepad.
const LORE_POWER := "On Power — \"The house drinks lightning like I drink my tea: greedily and at odd hours. If the lights are out, the old girl is only napping. Wake her gently; the fuses are in the usual impossible places.\" — C.G."
const LORE_LIGHT := "On Light — \"Light is the only honest visitor. It goes exactly where it is bent and never lies about it. I taught a beam to knock on my safe's door. Teach it the way — it forgets between visits.\" — C.G."
const LORE_TIME := "On Patience — \"My astronomical box keeps three secrets and demands a breath between them. Rush the lever and it sulks. Everything worth opening opens on a rhythm.\" — C.G."
const LORE_PRESSURE := "On Steam — \"Honest work. The boiler complains, the pipes gossip, and the gauges never flatter. Balance her humors and she will move mountains — or at least a vault wall.\" — C.G."
const LORE_FAMILY := "On Family — \"If you are reading this, you got further than my brother ever did. The strongbox holds the only page that matters; my machines each surrendered a number to whoever mastered them. I always meant to teach you myself.\" — C.G."

## Mrs. Puddle's event-triggered radio lines (shown in the subtitle bar).
const RADIO := {
	"run_start": "Radio check. The motorcade just left the gate — move like you mean it.",
	"power": "Lights! Just like his Tuesday demonstrations. Keep moving.",
	"puzzle_box": "That box beat every burglar for thirty years. He'd have liked you.",
	"safe": "The safe! He kept toffees in there. And apparently secrets.",
	"pressure": "The whole wing just sighed. That's the vault wall moving.",
	"vault": "The strongbox is through there. His machines gave you the numbers.",
	"strongbox": "That's his handwriting. That's the will — grab it and RUN.",
	"will": "You've got it! Out the front, quickly — before the suits see you.",
	"last_minute": "Headlights on the drive. One minute, no more.",
}

## Resident Evil-style completion grade for a winning run, from time
## elapsed on the 4:00 clock.
static func rank_for(elapsed: float) -> Dictionary:
	if elapsed <= 120.0:
		return {"letter": "S", "flavor": "He would have adopted you on the spot.",
			"color": Color(1.0, 0.84, 0.3)}
	if elapsed <= 150.0:
		return {"letter": "A", "flavor": "Sharp as his best apprentice.",
			"color": Color(0.85, 0.88, 0.95)}
	if elapsed <= 180.0:
		return {"letter": "B", "flavor": "A respectable Gearhart showing.",
			"color": Color(0.85, 0.62, 0.4)}
	if elapsed <= 210.0:
		return {"letter": "C", "flavor": "The lawyers were parking.",
			"color": Color(0.75, 0.75, 0.72)}
	return {"letter": "D", "flavor": "You could hear them knocking.",
		"color": Color(0.6, 0.58, 0.55)}
