extends Node

var sv_dedicated;
var cl_name;
var cl_chatting;

var players;
var mainmenu;
var world;
var chatmgr;

var prefab_player;
var prefab_freecam;

var players_path;

func _init():
	sv_dedicated = false;
	cl_name = "";
	cl_chatting = false;
	players_path = "env/players/";
	
	reset_variables();

func reset_variables():
	players = {};
	cl_chatting = false;

func _ready():
	get_tree().connect("network_peer_connected", self, "_peer_connected");
	get_tree().connect("network_peer_disconnected", self, "_peer_disconnected");
	
	get_tree().connect("connected_to_server", self, "_client_success");
	get_tree().connect("connection_failed", self, "_client_failed");
	get_tree().connect("server_disconnected", self, "_client_disconnected");
	
	prefab_player = load("res://prefabs/player.tscn");
	prefab_freecam = load("res://prefabs/cam_free.tscn");
	
	set_process_input(true);

func _input(ie):
	if (ie.type == InputEvent.KEY && !cl_chatting):
		if (ie.pressed && ie.scancode == KEY_ESCAPE):
			end_game();#get_tree().quit();

func host_game(port, max_clients):
	var net = NetworkedMultiplayerENet.new();
	net.create_server(port, max_clients);
	get_tree().set_network_peer(net);
	
	if (sv_dedicated):
		print("Server hosted on port ", port, ".");
		print("Max clients: ", max_clients);
	
	create_world();

func join_game(ip, port):
	var net = NetworkedMultiplayerENet.new();
	net.create_client(ip, port);
	get_tree().set_network_peer(net);

func end_game():
	mainmenu.enable_control();
	
	if (world != null):
		mainmenu.show();
		
		world.get_parent().remove_child(world);
		world.call_deferred("free");
		world = null;
	
	reset_variables();
	get_tree().call_deferred("set_network_peer", null);

func _peer_connected(id):
	if (!get_tree().is_network_server()):
		return;
	
	players[id] = null;

func _peer_disconnected(id):
	if (!get_tree().is_network_server()):
		return;
	
	if (players.has(id)):
		player_disconnected(id);
		players.erase(id);

func _client_success():
	rpc("player_ready", get_tree().get_network_unique_id(), cl_name);
	mainmenu.hide();

func _client_failed():
	mainmenu.set_message("Failed connecting to the server.");
	end_game();

func _client_disconnected():
	mainmenu.set_message("Disconnected from server.");
	end_game();

master func player_ready(id, name):
	if (!players.has(id) || players[id] != null || !get_tree().is_network_server()):
		return;
	
	players[id] = name;
	player_connected(id);

func player_connected(id):
	if (id != 1):
		rpc_id(id, "create_world");
		rpc_id(id, "clean_players");
		
		for i in world.get_node(players_path).get_children():
			var pid = i.get_name().to_int();
			if (pid == id):
				continue;
			var pos = i.get_global_transform().origin;
			rpc_id(id, "spawn_player", pid, players[pid], pos);
	
	var spawn_pos = Vector3(rand_range(-5, 5), 1, rand_range(-5, 5));
	rpc("spawn_player", id, players[id], spawn_pos);
	
	print("Player ",id," (", players[id], ") connected.");
	chatmgr.broadcast_msg(str(players[id])+" connected.");

func player_disconnected(id):
	rpc("despawn_player", id);
	
	print("Player ",id," (", players[id], ") disconnected.");
	chatmgr.broadcast_msg(str(players[id])+" disconnected.");

remote func create_world():
	world = load("res://scenes/world.tscn").instance();
	world.set_name("world");
	get_tree().get_root().call_deferred("add_child", world);

func create_host_player():
	if (!get_tree().is_network_server()):
		return;
	
	_peer_connected(1);
	player_ready(1, cl_name);

func world_ready():
	mainmenu.hide();
	
	if (!sv_dedicated):
		create_host_player();
	else:
		var inst = prefab_freecam.instance();
		inst.set_name("camera");
		world.get_node("env").add_child(inst);

remote func clean_players():
	if (!world):
		return;
	for i in world.get_node(players_path):
		i.queue_free();

sync func spawn_player(id, name, pos = null):
	if (player_by_id(id) != null):
		return;
	
	var inst = prefab_player.instance();
	inst.set_name(str(id));
	inst.player_name = str(name);
	if (pos != null):
		inst.set_global_transform(Transform(Matrix3(), pos));
	
	if (id == get_tree().get_network_unique_id()):
		inst.set_network_mode(NETWORK_MODE_MASTER);
	else:
		inst.set_network_mode(NETWORK_MODE_SLAVE);
	
	world.get_node(players_path).add_child(inst);

sync func despawn_player(id):
	var node = player_by_id(id);
	if (node == null):
		return;
	node.queue_free();

func player_by_id(id):
	var path = players_path+str(id);
	if (!world.has_node(path)):
		return null;
	return world.get_node(path);
