extends OptionButton

@export var intro_page: Button
@export var c_page: Button
@export var g_page: Button
@export var d_page: Button

func _ready():
	# Connect the item_selected signal to our function
	item_selected.connect(_on_option_selected)
	# Set initial state (show intro, hide others)
	_on_option_selected(0)

func _on_option_selected(index: int):
	# Hide all pages first
	intro_page.visible = false
	c_page.visible = false
	g_page.visible = false
	d_page.visible = false
	
	# Show the selected page based on index
	match index:
		0:
			intro_page.visible = true
		1:
			c_page.visible = true
		2:
			g_page.visible = true
		3:
			d_page.visible = true
