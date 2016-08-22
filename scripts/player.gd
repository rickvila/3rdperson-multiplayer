extends RigidBody

var player_name = "";

var accel = 12.0;
var deaccel = 15.0;
var jump_velocity = 7.5;

slave var local_dir = Vector3();
slave var local_input = [0];
sync var linear_velocity = Vector3();
sync var body_rotation = [0.0, 0.0];
sync var transform_pos = Vector3();
sync var camera_aim = Vector3();

var max_speed = 4.0;
var on_floor = false;
var moving = false;
var jumping = false;

var body;
var camera;
var camera_instance;
var models;
var skeleton;
var animation;

func _init():
	moving = false;
	player_name = "";

func _ready():
	body = get_node("body");
	camera = get_node("camera");
	camera_instance = get_node("camera/cam");
	models = get_node("body/models");
	skeleton = get_node("body/models/Armature/Skeleton");
	animation = get_node("body/models/AnimationPlayer");
	
	if (!is_network_master()):
		camera.queue_free();
	else:
		camera.set_active(true);
		camera.excl.append(self);
	
	set_fixed_process(true);

func _fixed_process(delta):
	var trans = body.get_transform();
	trans.basis = Matrix3(Quat(trans.basis).slerp(Quat(Vector3(0,1,0), body_rotation[1]), 5*delta));
	body.set_transform(trans);
	
	var hv_len = linear_velocity;
	hv_len.y = 0;
	hv_len = hv_len.length();
	
	if hv_len > 0.5:
		set_animation("walk-loop");
	else:
		set_animation("idle-loop");
	
	if (is_network_master()):
		if (gamestate.cl_chatting):
			local_input[0] = false;
		else:
			local_input[0] = Input.is_action_pressed("jump");
		
		rset("local_input", local_input);
		body_rotation[0] = camera.pitch;
	
	var bone_id = 6;
	var bone_pose = skeleton.get_bone_pose(bone_id);
	bone_pose.basis = bone_pose.basis.rotated(Vector3(1,0,0), deg2rad(-body_rotation[0]));
	skeleton.set_bone_custom_pose(bone_id, bone_pose);
	
	if (is_network_master()):
		camera_aim = -camera_instance.get_global_transform().basis[2];
		rset("camera_aim", camera_aim);

func set_animation(ani, speed = 1.0, force = false):
	if (animation.get_current_animation() != ani || force):
		animation.play(ani);
	if (animation.get_speed() != speed || force):
		animation.set_speed(speed);

func get_object_name():
	if (is_network_master()):
		return "";
	else:
		return player_name;

func _integrate_forces(state):
	if (is_network_master()):
		client_movement(state);
	
	if (get_tree().is_network_server()):
		network_movement(state);
	else:
		var transform = state.get_transform();
		transform.origin = transform.origin.linear_interpolate(transform_pos, 10*state.get_step());
		state.set_transform(transform);
		state.set_linear_velocity(linear_velocity);

func client_movement(state):
	local_dir = Vector3();
	var aim = camera_instance.get_global_transform().basis;
	
	if (!gamestate.cl_chatting):
		if Input.is_action_pressed("left"):
			local_dir -= aim[0];
		if Input.is_action_pressed("right"):
			local_dir += aim[0];
		if Input.is_action_pressed("forward"):
			local_dir -= aim[2];
		if Input.is_action_pressed("backward"):
			local_dir += aim[2];
	
	local_dir.y = 0;
	local_dir = local_dir.normalized();
	
	if (local_dir.length() > 0.0):
		body_rotation[1] = -atan2(local_dir.x, local_dir.z);
	
	if (camera.aiming):
		body_rotation[1] = -deg2rad(camera.yaw-180);
	
	rset("local_dir", local_dir);
	rset("body_rotation", body_rotation);

func network_movement(state):
	linear_velocity = state.get_linear_velocity()
	var g = state.get_total_gravity();
	var delta = state.get_step();
	
	linear_velocity += g*delta # Apply gravity
	
	var up = -g.normalized() # (up is against gravity)
	var vv = up.dot(linear_velocity) # Vertical velocity
	var hv = linear_velocity - up*vv # Horizontal velocity
	
	var hdir = hv.normalized() # Horizontal direction
	var hspeed = hv.length() # Horizontal speed
	
	var floor_velocity;
	var onfloor = false;
	
	if (state.get_contact_count() > 0):
		for i in range(state.get_contact_count()):
			if (state.get_contact_local_shape(i) != 1):
				continue
			
			onfloor = true
			break
	
	var jump_attempt = local_input[0];
	var target_dir = (local_dir - up*local_dir.dot(up)).normalized();
	
	moving = false;
	
	if (onfloor):
		if (local_dir.length() > 0.1):
			hdir = target_dir;
			
			if (hspeed < max_speed):
				hspeed = min(hspeed+(accel*delta), max_speed);
			else:
				hspeed = max_speed;
			
			moving = true;
		else:
			hspeed -= deaccel*delta;
			if (hspeed < 0):
				hspeed = 0;
		
		hv = hdir*hspeed;
		
		if (not jumping and jump_attempt):
			vv = jump_velocity;
			
			jumping = true;
	else:
		var hs;
		if (local_dir.length() > 0.1):
			hv += target_dir*(accel*0.2)*delta;
			if (hv.length() > max_speed):
				hv = hv.normalized()*max_speed;
	
	if (jumping and vv < 0):
		jumping = false;
	
	linear_velocity = hv + up*vv;
	on_floor = onfloor;
	
	state.set_linear_velocity(linear_velocity);
	rset("linear_velocity", linear_velocity);
	
	transform_pos = state.get_transform().origin;
	rset("transform_pos", state.get_transform().origin);
