extends MeshInstance3D
@onready var light = $SpotLight3D
@onready var timer = $batteryTimer
var battery = 100
var on = false

func _ready() -> void:
	$Area3D.add_to_group("item")
	timer.wait_time = 2

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("use") and get_parent().name == "items":
		if battery > 0:
			on = not on
			light.visible = on
			$AudioStreamPlayer3D.play()
			
			if on:
				timer.start()
			else:
				timer.stop()
		else:
			on = false
			light.visible = false
			$AudioStreamPlayer3D.play()
			
func _on_battery_timer_timeout() -> void:
	battery -= 1
	
	if battery <= 0:
		battery = 0
		on = false
		light.visible = false
		timer.stop()
