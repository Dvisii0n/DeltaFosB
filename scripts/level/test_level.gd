extends Node3D
## Test level setup: builds the navigation mesh (the walkable area enemies path on)
## when the level starts, so you never have to press "Bake" by hand.
## If you move boxes around, it just re-bakes next run.
## Only nodes in the group "navigation_mesh_source_group" (Geometry and Dummies) count
## as obstacles. Put new level geometry in that group too.

@onready var nav_region: NavigationRegion3D = $NavigationRegion3D


func _ready() -> void:
	nav_region.bake_navigation_mesh()
