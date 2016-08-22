extends RigidBody

slave var transform = Transform();

func _ready():
	set_can_sleep(false);

func _integrate_forces(state):
	if (get_tree().is_network_server()):
		rset("transform", state.get_transform());
	else:
		var trans = state.get_transform();
		trans.origin = trans.origin.linear_interpolate(transform.origin, 10*state.get_step());
		trans.basis = transform.basis;
		state.set_transform(trans);
