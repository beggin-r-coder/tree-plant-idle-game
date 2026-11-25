class_name GameData
extends RefCounted
## Static balancing + content data. Tweak numbers here to rebalance the game.

## One entry per plant "level". Index in this array == plant level - 1.
##  growth      : growth points needed for one tree to fully grow (1 click = click power points)
##  reward      : coins paid when a tree finishes growing
##  unlock_cost : coins needed to unlock this plant type
##  short       : short name shown under the plant buttons
##  radius      : how much room the tree needs in the forest (world units)
##  auto_cost   : base price of the Planter Drone (automation) for this plant
##  auto_rate   : growth points per second the drone adds, per drone level
##  co2         : approx. kg of CO2 one mature tree of this kind absorbs per year (kid-friendly estimate)
const PLANTS: Array[Dictionary] = [
	{
		"id": "bush", "short": "Bush", "radius": 0.45, "name": "Berry Bush", "growth": 10.0, "reward": 5.0,
		"unlock_cost": 0.0, "auto_cost": 15.0, "auto_rate": 1.0, "co2": 5.0,
		"fact": "Bushes give food and shelter to birds and insects, and their roots hold soil in place so rain can't wash it away.",
	},
	{
		"id": "oak", "short": "Oak", "radius": 0.75, "name": "Oak Tree", "growth": 30.0, "reward": 22.0,
		"unlock_cost": 100.0, "auto_cost": 120.0, "auto_rate": 2.0, "co2": 22.0,
		"fact": "A single big oak tree can be home to hundreds of different insects, birds and other creatures!",
	},
	{
		"id": "pine", "short": "Pine", "radius": 0.55, "name": "Pine Tree", "growth": 80.0, "reward": 70.0,
		"unlock_cost": 750.0, "auto_cost": 900.0, "auto_rate": 4.0, "co2": 18.0,
		"fact": "Pine trees stay green all winter. Their needles have a waxy coat that helps them save water.",
	},
	{
		"id": "birch", "short": "Birch", "radius": 0.5, "name": "Birch Tree", "growth": 200.0, "reward": 210.0,
		"unlock_cost": 4000.0, "auto_cost": 5000.0, "auto_rate": 8.0, "co2": 15.0,
		"fact": "Birch trees are 'pioneer' trees: they are often the first to grow on empty land and help a brand-new forest begin.",
	},
	{
		"id": "cherry", "short": "Cherry", "radius": 0.7, "name": "Cherry Blossom", "growth": 500.0, "reward": 650.0,
		"unlock_cost": 25000.0, "auto_cost": 30000.0, "auto_rate": 15.0, "co2": 20.0,
		"fact": "Flowering trees feed bees and butterflies. These pollinators help grow much of the fruit and vegetables we eat!",
	},
	{
		"id": "sequoia", "short": "Sequoia", "radius": 0.85, "name": "Giant Sequoia", "growth": 1500.0, "reward": 2400.0,
		"unlock_cost": 150000.0, "auto_cost": 180000.0, "auto_rate": 30.0, "co2": 60.0,
		"fact": "Giant sequoias are among the biggest living things on Earth and can live for more than 3,000 years!",
	},
]

## Ecosystem milestones, reached by total trees planted.
##  feature : world change that appears (handled in World)
##  animal  : animal species that moves in (handled in AnimalFactory)
const STAGES: Array[Dictionary] = [
	{
		"trees": 0, "name": "Barren Land", "feature": "", "animal": "", "count": 0,
		"ground": Color(0.52, 0.41, 0.3), "sky": Color(0.72, 0.74, 0.72),
		"title": "Welcome, Little Forester!",
		"fact": "This land has lost its trees. Click to plant and grow your first bush and bring nature back!",
	},
	{
		"trees": 5, "name": "First Sprouts", "feature": "grass", "animal": "butterfly", "count": 7,
		"ground": Color(0.50, 0.58, 0.32), "sky": Color(0.68, 0.80, 0.86),
		"title": "Butterflies have arrived!",
		"fact": "Grass is growing again! Butterflies help flowers make seeds. Seeing them means nature is getting healthier.",
	},
	{
		"trees": 20, "name": "Flowing River", "feature": "river", "animal": "bird", "count": 6,
		"ground": Color(0.42, 0.58, 0.30), "sky": Color(0.62, 0.82, 0.92),
		"title": "A river is flowing!",
		"fact": "Tree roots soak up rain and keep rivers clean, so forests help give us fresh water. Birds came back to drink, and they spread seeds as they fly!",
	},
	{
		"trees": 50, "name": "Blooming Meadow", "feature": "flowers", "animal": "rabbit", "count": 5,
		"ground": Color(0.38, 0.57, 0.28), "sky": Color(0.58, 0.83, 0.95),
		"title": "Flowers and rabbits!",
		"fact": "Wildflowers are food for bees. Rabbits nibble the plants and dig burrows that let air and water into the soil.",
	},
	{
		"trees": 100, "name": "Peaceful Woodland", "feature": "pond", "animal": "deer", "count": 4,
		"ground": Color(0.34, 0.55, 0.27), "sky": Color(0.55, 0.82, 0.97),
		"title": "Deer moved into your woodland!",
		"fact": "A pond appeared! Wetlands clean water and are home to frogs and fish. Deer need forests to hide and find food.",
	},
	{
		"trees": 200, "name": "Wild Forest", "feature": "mountains", "animal": "wolf", "count": 3,
		"ground": Color(0.31, 0.53, 0.26), "sky": Color(0.52, 0.80, 0.98),
		"title": "A wolf pack has returned!",
		"fact": "Wolves keep nature in balance. When wolves returned to Yellowstone Park, the forests and rivers there began to recover!",
	},
	{
		"trees": 400, "name": "Jungle Heart", "feature": "jungle", "animal": "tiger", "count": 2,
		"ground": Color(0.29, 0.52, 0.25), "sky": Color(0.50, 0.79, 0.99),
		"title": "Tigers are back!",
		"fact": "Tigers need big, connected forests. Protecting a tiger's home protects thousands of other plants and animals too.",
	},
	{
		"trees": 800, "name": "Living Earth", "feature": "rainbow", "animal": "elephant", "count": 2,
		"ground": Color(0.28, 0.53, 0.27), "sky": Color(0.48, 0.80, 1.0),
		"title": "You are an Earth Guardian!",
		"fact": "Elephants are 'gardeners of the forest': they spread seeds far and wide. You rebuilt a whole ecosystem, just like the UN goal 'Life on Land' (SDG 15)!",
	},
]

## The intro cinematic (scenes/intro.tscn) is hidden for now. Set to true to play it on first launch
## and show "Watch intro" in the shop again.
const INTRO_ENABLED := false

const CLICK_BASE_COST := 10.0
const CLICK_COST_GROWTH := 1.55
const FERT_BASE_COST := 300.0
const FERT_COST_GROWTH := 4.0
const FERT_MULT := 1.25
const AUTO_COST_GROWTH := 1.15
const OFFLINE_CAP_SECONDS := 8.0 * 3600.0


static func format_number(v: float) -> String:
	var suffixes := ["", "K", "M", "B", "T", "Qa", "Qi"]
	var i := 0
	var n := v
	while absf(n) >= 1000.0 and i < suffixes.size() - 1:
		n /= 1000.0
		i += 1
	if i == 0:
		return str(int(floor(n)))
	if n >= 100.0:
		return "%d%s" % [int(n), suffixes[i]]
	return "%.1f%s" % [n, suffixes[i]]
