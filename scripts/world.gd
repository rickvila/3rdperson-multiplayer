extends Node

var time;

func _init():
	time = 0.0;

func _ready():
	gamestate.world_ready();
	
	set_process(true);

func _process(delta):
	time += delta;
